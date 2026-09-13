"""Healthy script playback for all original level-one Arm ground factory products."""
import json
from pathlib import Path
from native_factory_reference import FactoryReference
from native_cob_reference import EXE_HASH


def main():
    root = Path('local/unit-assets')
    index = json.loads((root / 'index.json').read_text())
    units = index['build_menus']['armlab'] + index['build_menus']['armvp']
    folder = Path('local/mobile-scripts')
    folder.mkdir(exist_ok=True)
    executable = Path('local/original/TotalA.exe').read_bytes()
    events = {0: ('Create', []), 31: ('StartMoving', []), 35: ('Activate', []),
              50: ('AimPrimary', [8192, 1024]), 70: ('StartBuilding', [2048, 0]),
              90: ('StopMoving', []), 110: ('StopBuilding', []), 120: ('Deactivate', []),
              130: ('StartMoving', []), 190: ('StopMoving', [])}
    for unit in units:
        native = FactoryReference(executable, (root / unit / 'script.cob').read_bytes())
        functions = {item['name'] for item in native.program['functions']}
        snapshots = []
        for tick in range(301):
            if tick == 30:
                native.read_values[17] = 0
            if tick:
                native.step()
                snapshots.append(dict(tick=tick, action='step', args=[], state=native.snapshot()))
            if tick in events:
                action, args = events[tick]
                if action in functions:
                    native.invoke(action, args)
                    snapshots.append(dict(tick=tick, action=action, args=args, state=native.snapshot()))
        (folder / f'{unit}.json').write_text(json.dumps(dict(unit=unit, snapshots=snapshots)), encoding='utf-8')
        print(f'NATIVE_MOBILE_REFERENCE {unit}: {len(snapshots)} snapshots', flush=True)
    (folder / 'index.json').write_text(json.dumps(dict(units=units, exe_sha256=EXE_HASH)), encoding='utf-8')


if __name__ == '__main__':
    main()
