"""Original healthy Create playback for Core structures whose scripts have no activation lifecycle."""
import json
from pathlib import Path
from native_factory_reference import FactoryReference
from native_cob_reference import EXE_HASH

UNITS = ['corestor', 'cormstor', 'cordrag', 'cormine1', 'cormine2', 'cormine3', 'cormine4', 'cormine5', 'cormine6']


def main():
    root = Path('local/unit-assets')
    folder = Path('local/structures')
    folder.mkdir(exist_ok=True)
    executable = Path('local/original/TotalA.exe').read_bytes()
    for unit in UNITS:
        native = FactoryReference(executable, (root / unit / 'script.cob').read_bytes())
        native.invoke('Create', [])
        snapshots = [dict(tick=0, action='Create', state=native.snapshot())]
        for tick in range(1, 601):
            # Construction finishes at tick 30, matching the other building oracles.
            if tick == 30:
                native.read_values[17] = 0
            native.step()
            snapshots.append(dict(tick=tick, action='step', state=native.snapshot()))
        (folder / f'{unit}.json').write_text(json.dumps(dict(unit=unit, snapshots=snapshots)), encoding='utf-8')
        print(f'NATIVE_STRUCTURE_REFERENCE {unit}: {len(snapshots)} snapshots', flush=True)
    (folder / 'index.json').write_text(json.dumps(dict(units=UNITS, exe_sha256=EXE_HASH)), encoding='utf-8')


if __name__ == '__main__':
    main()
