"""Script playback for all original level-one Arm and Core ground factory products.

Default: the healthy scenario (local/mobile-scripts). --damaged: the damaged-seeded scenario
(local/mobile-scripts/damaged): 600 ticks, shared RNG seeded through 0x4b6ca0, health read 100 -> 50 -> 20,
recording EMIT_SFX callbacks and the final RNG seed. It adds RAND users outside the level-one menus.
"""
import argparse
import json
from pathlib import Path
from native_factory_reference import FactoryReference
from native_cob_reference import EXE_HASH

HEALTHY_EVENTS = {0: ('Create', []), 31: ('StartMoving', []), 35: ('Activate', []),
                  50: ('AimPrimary', [8192, 1024]), 70: ('StartBuilding', [2048, 0]),
                  90: ('StopMoving', []), 110: ('StopBuilding', []), 120: ('Deactivate', []),
                  130: ('StartMoving', []), 190: ('StopMoving', [])}
# The healthy lifecycle, repeated while damaged so smoke overlaps motion, aiming and building.
DAMAGED_EVENTS = dict(HEALTHY_EVENTS)
DAMAGED_EVENTS.update({tick + 300: event for tick, event in HEALTHY_EVENTS.items() if tick})
DAMAGED_SEED_INPUT = 0x1234
HEALTH_SCHEDULE = {0: 100, 200: 50, 400: 20}
DAMAGED_EXTRA_UNITS = ['corpyro']


def run(executable, cob, events, ticks, health=None, seed=None):
    native = FactoryReference(executable, cob)
    if seed is not None:
        native.seed(seed)
    seed_start = native.rng_seed()
    functions = {item['name'] for item in native.program['functions']}
    snapshots = []
    for tick in range(ticks + 1):
        if tick == 30:
            native.read_values[17] = 0
        if health and tick in health:
            native.read_values[4] = health[tick]
        if tick:
            native.step()
            snapshots.append(dict(tick=tick, action='step', args=[], state=native.snapshot()))
        if tick in events:
            action, args = events[tick]
            if action in functions:
                native.invoke(action, args)
                snapshots.append(dict(tick=tick, action=action, args=args, state=native.snapshot()))
    return dict(snapshots=snapshots, seed_start=seed_start, seed_end=native.rng_seed(), sfx=native.sfx, dropped=native.dropped)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--damaged', action='store_true', help='write the damaged-seeded scenario instead')
    damaged = parser.parse_args().damaged
    root = Path('local/unit-assets')
    index = json.loads((root / 'index.json').read_text())
    units = [unit for factory in ['armlab', 'armvp', 'corlab', 'corvp'] for unit in index['build_menus'][factory]]
    folder = Path('local/mobile-scripts')
    if damaged:
        units += [unit for unit in DAMAGED_EXTRA_UNITS if (root / unit / 'script.cob').exists() and unit not in units]
        folder = folder / 'damaged'
    folder.mkdir(parents=True, exist_ok=True)
    executable = Path('local/original/TotalA.exe').read_bytes()
    for unit in units:
        cob = (root / unit / 'script.cob').read_bytes()
        if damaged:
            result = run(executable, cob, DAMAGED_EVENTS, 600, HEALTH_SCHEDULE, DAMAGED_SEED_INPUT)
        else:
            result = run(executable, cob, HEALTHY_EVENTS, 300)
        (folder / f'{unit}.json').write_text(json.dumps(dict(unit=unit, **result)), encoding='utf-8')
        print(f'NATIVE_MOBILE_REFERENCE {unit}: {len(result["snapshots"])} snapshots, {len(result["sfx"])} sfx, '
              f'seed {result["seed_start"]:#x} -> {result["seed_end"]:#x}', flush=True)
    scenario = dict(ticks=600, health={str(k): v for k, v in HEALTH_SCHEDULE.items()}, seed_input=DAMAGED_SEED_INPUT) if damaged else dict(ticks=300)
    (folder / 'index.json').write_text(json.dumps(dict(units=units, exe_sha256=EXE_HASH, scenario=scenario)), encoding='utf-8')


if __name__ == '__main__':
    main()
