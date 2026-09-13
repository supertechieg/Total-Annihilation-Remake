"""Original pose setters and origin traversal on prepared real tank geometry.

Uses prior native firing snapshots; does not reproduce the original model loader.
Records are arranged in COB name order, with parent pointers rebuilt by name.
"""
import json
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH, CONTEXT, STATICS, SCRIPT
from cob import signed

MODEL, GEOMETRY, OUTPUT = 0x100a000, 0x100c000, 0x100b000


def main():
    cases = []
    for unit in ['armflash', 'corraid']:
        root = Path('local/unit-assets') / unit
        model = json.loads((root / 'unit.json').read_text())['model']
        program = json.loads((root / 'script.json').read_text())
        native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), (root / 'script.cob').read_bytes())
        # Earlier index-based script oracles did not need relocated name strings.
        for table_offset, count in [(0x1c, len(program['functions'])), (0x20, len(program['pieces']))]:
            table = native.read(SCRIPT + table_offset)
            for index in range(count):
                native.write(table + index * 4, SCRIPT + native.read(table + index * 4))
        native.write(CONTEXT + 0x540, MODEL)
        native.write(UNIT + 0x9e, MODEL)
        native.write(UNIT + 0x9a, CONTEXT)
        by_name = {piece['name'].lower(): piece for piece in model['pieces']}
        names = [name.lower() for name in program['pieces']]
        names += [name for name in by_name if name not in names]
        native.write(MODEL, len(names))
        for index, name in enumerate(names):
            piece = by_name[name]
            record, geom = MODEL + 0x22 + index * 0x36, GEOMETRY + index * 0x40
            native.write(record, geom)
            parent = piece['parent']
            native.write(record + 0x32, 0 if parent < 0 else MODEL + 0x22 + names.index(model['pieces'][parent]['name'].lower()) * 0x36)
            for axis in range(3):
                native.write(geom + 0x10 + axis * 4, piece['offset'][axis])
        trace_path = Path('local/firing/native-trace.json') if unit == 'armflash' else Path('local/firing/corraid/native-trace.json')
        trace = json.loads(trace_path.read_text())
        for item in trace['snapshots']:
            if 'query_piece' not in item:
                continue
            poses = item['state']['pieces']
            for index, value in enumerate(item['state']['statics']):
                native.write(STATICS + index * 4, value)
            for index, pose in enumerate(poses):
                for axis in range(3):
                    native.call(0x480c50, [index, axis, pose['position'][axis]])
                    native.call(0x480ce0, [index, axis, pose['rotation'][axis]])
            name = names[item['query_piece']]
            for heading in [0, 8192, 32768, 49152]:
                native.short(UNIT + 0x64, 0)
                native.short(UNIT + 0x66, heading)
                native.short(UNIT + 0x68, 0)
                native.call(0x43def0, [OUTPUT, UNIT, item['query_piece']])
                cases.append(dict(unit=unit, poses=poses, name=name, angles=[0, heading, 0],
                                  expected=[signed(native.read(OUTPUT + axis * 4)) for axis in range(3)]))
                native.call(0x43e2e0, [UNIT, OUTPUT, 0])
                cases.append(dict(unit=unit, poses=poses, statics=item['state']['statics'], aim_from=True, angles=[0, heading, 0],
                                  expected=[signed(native.read(OUTPUT + axis * 4)) for axis in range(3)]))
                function_names = native.read(SCRIPT + 0x1c)
                aim_index = next(i for i, function in enumerate(program['functions']) if function['name'] == 'AimFromPrimary')
                address = function_names + aim_index * 4
                saved_name = native.read(address)
                native.write(address, native.read(function_names))  # Hide AimFrom by aliasing another name.
                native.call(0x43e2e0, [UNIT, OUTPUT, 0])
                native.write(address, saved_name)
                cases.append(dict(unit=unit, poses=poses, statics=item['state']['statics'], aim_from=True, fallback=True, angles=[0, heading, 0],
                                  expected=[signed(native.read(OUTPUT + axis * 4)) for axis in range(3)]))
    folder = Path('local/piece-origin')
    folder.mkdir(exist_ok=True)
    (folder / 'native-tanks.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_TANK_ORIGINS {len(cases)} cases')


if __name__ == '__main__':
    main()
