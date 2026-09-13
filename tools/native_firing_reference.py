"""Tank firing-script oracle with supplied callback timing, not native shot scheduling."""
import argparse
import json
from pathlib import Path
from native_factory_reference import FactoryReference
from native_cob_reference import CONTEXT, EXE_HASH
from cob import signed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit', choices=['armflash', 'corraid', 'armstump', 'armham'], default='armflash')
    unit = parser.parse_args().unit
    native = FactoryReference(Path('local/original/TotalA.exe').read_bytes(), Path(f'local/unit-assets/{unit}/script.cob').read_bytes())
    native.read_values[17] = 0
    events = {0: [('Create', []), ('SetMaxReloadTime', [400])],
              1: [('AimPrimary', [8192, 1024])], 120: [('AimPrimary', [-8192, 2048])],
              180: [('AimPrimary', [4096, 0])]}
    for tick in [50, 53, 56, 80, 83, 86, 160, 163, 166]:
        events[tick] = [('QueryPrimary', [0]), ('FirePrimary', [])]
    if unit in ('corraid', 'armstump'):
        # Exercise cannon recoil recovery and hit-induced rocking independently
        # of the still-unreconstructed ballistic projectile host.
        events[100] = [('HitByWeapon', [1024, -2048])]
        events[210] = [('HitByWeapon', [-2048, 1024])]
    snapshots = []
    queries = []
    for tick in range(301):
        if tick:
            native.step()
            snapshots.append(dict(tick=tick, action='step', args=[], state=native.snapshot()))
        for action, args in events.get(tick, []):
            slot = next(i for i in range(8) if native.read(CONTEXT + 0x1c + i * 0xa4) == 0)
            native.invoke(action, args)
            item = dict(tick=tick, action=action, args=args, state=native.snapshot())
            if action == 'QueryPrimary':
                if native.read(CONTEXT + 0x1c + slot * 0xa4) != 0:
                    raise AssertionError('Query did not return synchronously')
                item['query_piece'] = signed(native.read(CONTEXT + 0x1c + slot * 0xa4 + 0x24))
                queries.append(dict(tick=tick, piece=item['query_piece']))
            snapshots.append(item)
    folder = Path('local/firing') if unit == 'armflash' else Path('local/firing') / unit
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native-trace.json').write_text(json.dumps(dict(unit=unit, exe_sha256=EXE_HASH, snapshots=snapshots, queries=queries)), encoding='utf-8')
    print(f'NATIVE_FIRING_REFERENCE {unit}: {len(snapshots)} snapshots; queries={queries}')


if __name__ == '__main__':
    main()
