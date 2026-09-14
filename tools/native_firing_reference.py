"""Tank firing-script oracle with supplied callback timing, not native shot scheduling.

--damaged writes native-trace-damaged.json: the same callbacks repeated over 600 ticks with the shared RNG
seeded through 0x4b6ca0 and the health read stepping 100 -> 50 -> 20, recording EMIT_SFX and the final seed.
"""
import argparse
import json
from pathlib import Path
from native_factory_reference import FactoryReference
from native_cob_reference import CONTEXT, EXE_HASH
from cob import signed

UNITS = ['armflash', 'corraid', 'armstump', 'armham', 'armpw', 'armrock', 'armwar', 'armsam', 'armjeth',
         'corthud', 'corlevlr', 'corstorm', 'cormist', 'corcrash',
         'armfav', 'corfav', 'corgator', 'corak', 'armcom', 'corcom', 'corpyro']
DAMAGED_SEED_INPUT = 0x1234
HEALTH_SCHEDULE = {0: 100, 200: 50, 400: 20}


def scenario(unit, damaged):
    events = {0: [('Create', []), ('SetMaxReloadTime', [400])],
              1: [('AimPrimary', [8192, 1024])], 120: [('AimPrimary', [-8192, 2048])],
              180: [('AimPrimary', [4096, 0])]}
    for tick in [50, 53, 56, 80, 83, 86, 160, 163, 166]:
        events[tick] = [('QueryPrimary', [0]), ('FirePrimary', [])]
    if unit in ('corraid', 'armstump', 'corlevlr', 'cormist', 'armfav', 'corfav', 'corgator'):
        # Exercise cannon recoil recovery and hit-induced rocking independently
        # of the still-unreconstructed ballistic projectile host.
        events[100] = [('HitByWeapon', [1024, -2048])]
        events[210] = [('HitByWeapon', [-2048, 1024])]
    if unit in ('armcom', 'corcom'):
        # Commander D-gun (weapon 3) script callbacks after the primary laser sequence.
        events[200] = [('AimTertiary', [-4096, 512])]
        for tick in (230, 233):
            events[tick] = [('QueryTertiary', [0]), ('FireTertiary', [])]
    if damaged:
        for tick, calls in list(events.items()):
            if tick:
                events[tick + 300] = list(calls)
    return events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit', choices=UNITS, default='armflash')
    parser.add_argument('--damaged', action='store_true')
    options = parser.parse_args()
    unit, damaged = options.unit, options.damaged
    native = FactoryReference(Path('local/original/TotalA.exe').read_bytes(), Path(f'local/unit-assets/{unit}/script.cob').read_bytes())
    native.read_values[17] = 0
    if damaged:
        native.seed(DAMAGED_SEED_INPUT)
    seed_start = native.rng_seed()
    events = scenario(unit, damaged)
    ticks = 600 if damaged else 300
    functions = {item['name'] for item in native.program['functions']}
    snapshots = []
    queries = []
    for tick in range(ticks + 1):
        if damaged and tick in HEALTH_SCHEDULE:
            native.read_values[4] = HEALTH_SCHEDULE[tick]
        if tick:
            native.step()
            snapshots.append(dict(tick=tick, action='step', args=[], state=native.snapshot()))
        for action, args in events.get(tick, []):
            # The engine skips callbacks a script does not define (corthud/corstorm lack SetMaxReloadTime, corpyro FirePrimary).
            if action not in functions:
                continue
            slot = native.free_slot()
            started = native.invoke(action, args)
            item = dict(tick=tick, action=action, args=args, state=native.snapshot())
            if action in ('QueryPrimary', 'QueryTertiary'):
                if started and native.read(CONTEXT + 0x1c + slot * 0xa4) != 0:
                    raise AssertionError('Query did not return synchronously')
                # A dropped query leaves the engine's initial local (0) in place (0x4b0c4f).
                item['query_piece'] = signed(native.read(CONTEXT + 0x1c + slot * 0xa4 + 0x24)) if started else 0
                queries.append(dict(tick=tick, piece=item['query_piece']))
            if not started:
                item['dropped'] = True
            snapshots.append(item)
    folder = Path('local/firing') if unit == 'armflash' else Path('local/firing') / unit
    folder.mkdir(parents=True, exist_ok=True)
    name = 'native-trace-damaged.json' if damaged else 'native-trace.json'
    (folder / name).write_text(json.dumps(dict(unit=unit, exe_sha256=EXE_HASH, snapshots=snapshots, queries=queries,
                                               seed_start=seed_start, seed_end=native.rng_seed(), sfx=native.sfx, dropped=native.dropped,
                                               health={str(k): v for k, v in HEALTH_SCHEDULE.items()} if damaged else {})), encoding='utf-8')
    print(f'NATIVE_FIRING_REFERENCE {unit}{" damaged" if damaged else ""}: {len(snapshots)} snapshots; sfx={len(native.sfx)}; '
          f'seed {seed_start:#x} -> {native.rng_seed():#x}; dropped={len(native.dropped)}; queries={queries}')


if __name__ == '__main__':
    main()
