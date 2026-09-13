"""Original loader axis conversion, model update and SweetSpot wrapper on tanks."""
import json
import sys
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH, CONTEXT, STATICS, SCRIPT
from cob import signed

MODEL, OUTPUT = 0x1500000, 0x15f0000


def main():
    cases = []
    roster = '--roster' in sys.argv
    units = sorted(p.parent.name for p in Path('local/unit-assets').glob('*/unit.json')) if roster else ['armflash', 'corraid', 'armstump', 'armham']
    for unit in units:
        root = Path('local/unit-assets') / unit
        model = json.loads((root / 'unit.json').read_text())['model']
        program = json.loads((root / 'script.json').read_text())
        native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), (root / 'script.cob').read_bytes())
        native.mu.mem_map(MODEL, 0x100000)
        for offset, count in [(0x1c, len(program['functions'])), (0x20, len(program['pieces']))]:
            table = native.read(SCRIPT + offset)
            for index in range(count):
                native.write(table + index * 4, SCRIPT + native.read(table + index * 4))
        native.write(CONTEXT + 0x540, MODEL)
        native.write(UNIT + 0x9e, MODEL)
        native.write(UNIT + 0x9a, CONTEXT)
        by_name = {p['name'].lower(): p for p in model['pieces']}
        names = [name.lower() for name in program['pieces']]
        names += [name for name in by_name if name not in names]
        parents = [p['parent'] for p in model['pieces']]
        def record(model_index):
            return MODEL + 0x22 + names.index(model['pieces'][model_index]['name'].lower()) * 0x36
        native.write(MODEL, len(names))
        native.write(MODEL + 0x1e, record(parents.index(-1)))
        for i, piece in enumerate(model['pieces']):
            rec, geom = record(i), MODEL + 0x1000 + i * 0x4000
            raw, runtime = geom + 0x100, geom + 0x2000
            native.write(rec, geom)
            native.write(rec + 0x22, runtime)
            native.write(geom + 4, len(piece['vertices']))
            native.write(geom + 0x24, raw)
            for axis in range(3):
                native.write(geom + 0x10 + axis * 4, piece['offset'][axis])
            for v, vertex in enumerate(piece['vertices']):
                for axis, value in enumerate(vertex):
                    native.write(raw + v * 12 + axis * 4, value)
            native.call(0x4cb590, [geom])
            children = [j for j, parent in enumerate(parents) if parent == i]
            siblings = [j for j, parent in enumerate(parents) if parent == parents[i] and j > i]
            native.write(rec + 0x2e, record(children[0]) if children else 0)
            native.write(rec + 0x2a, record(siblings[0]) if siblings else 0)
        path = Path('local/firing/native-trace.json') if unit == 'armflash' else Path(f'local/firing/{unit}/native-trace.json')
        snapshots = json.loads(path.read_text())['snapshots'] if not roster else [dict(query_piece=0, state=dict(
            pieces=[dict(name=name, position=[0, 0, 0], rotation=[0, 0, 0]) for name in program['pieces']],
            statics=[]))]
        for item in snapshots:
            if 'query_piece' not in item:
                continue
            poses = item['state']['pieces']
            for i, value in enumerate(item['state']['statics']):
                native.write(STATICS + i * 4, value)
            for i, pose in enumerate(poses):
                for axis in range(3):
                    native.write(MODEL + 0x22 + i * 0x36 + 4 + axis * 4, pose['position'][axis])
                    native.short(MODEL + 0x22 + i * 0x36 + 0x10 + axis * 2, pose['rotation'][axis])
            for heading in [0, 8192, 32768, 49152]:
                angles, position = [0, heading, 0], [100 * 65536, 7 * 65536, 200 * 65536]
                for axis in range(3):
                    native.short(UNIT + 0x64 + axis * 2, angles[axis])
                    native.write(UNIT + 0x6a + axis * 4, position[axis])
                native.write(MODEL + 8, 1)
                for i in range(len(names)):
                    native.short(MODEL + 0x22 + i * 0x36 + 0x26, 0)
                native.call(0x45ab10, [UNIT])
                native.call(0x43e3c0, [UNIT, OUTPUT])
                cases.append(dict(unit=unit, poses=poses, statics=item['state']['statics'], angles=angles, position=position,
                                  expected=[signed(native.read(OUTPUT + axis * 4)) for axis in range(3)]))
    Path('local/target-point').mkdir(exist_ok=True)
    Path('local/target-point/' + ('roster.json' if roster else 'tanks.json')).write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_TANK_TARGETS {len(cases)} cases')


if __name__ == '__main__':
    main()
