"""Compare complete native model update on supplied geometry and pose trees."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH
from cob import signed

MODEL = 0x1500000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(MODEL, 0x10000)
    rng = random.Random(0x45ab10)
    cases = []
    for index in range(300):
        native.mu.mem_write(MODEL, bytes(0x10000))
        pieces = []
        for number in range(1 + index % 7):
            pieces.append(dict(parent=-1 if number == 0 else rng.randrange(number),
                               offset=[rng.randrange(-1000000, 1000001) for _ in range(3)],
                               move=[rng.randrange(-65536, 65537) for _ in range(3)],
                               rotation=[rng.randrange(65536) for _ in range(3)],
                               vertices=[[rng.randrange(-1000000, 1000001) for _ in range(3)] for _ in range(number % 5)]))
        angles = [rng.randrange(65536) for _ in range(3)]
        native.write(UNIT + 0x9e, MODEL)
        native.write(MODEL, len(pieces))
        native.write(MODEL + 8, 1)
        native.write(MODEL + 0x1e, MODEL + 0x22)
        for axis in range(3):
            native.short(UNIT + 0x64 + axis * 2, angles[axis])
            native.short(MODEL + 0x18 + axis * 2, angles[axis])
        for number, piece in enumerate(pieces):
            record = MODEL + 0x22 + number * 0x36
            geom = MODEL + 0x1000 + number * 0x400
            raw, runtime = geom + 0x80, geom + 0x180
            native.write(record, geom)
            native.write(record + 0x22, runtime)
            native.write(geom + 4, len(piece['vertices']))
            native.write(geom + 0x24, raw)
            children = [i for i, p in enumerate(pieces) if p['parent'] == number]
            siblings = [i for i, p in enumerate(pieces) if p['parent'] == piece['parent'] and i > number]
            native.write(record + 0x2e, MODEL + 0x22 + children[0] * 0x36 if children else 0)
            native.write(record + 0x2a, MODEL + 0x22 + siblings[0] * 0x36 if siblings else 0)
            for axis in range(3):
                native.write(geom + 0x10 + axis * 4, piece['offset'][axis])
                native.write(record + 4 + axis * 4, piece['move'][axis])
                native.short(record + 0x10 + axis * 2, piece['rotation'][axis])
            for v, vertex in enumerate(piece['vertices']):
                for axis, value in enumerate(vertex):
                    native.write(raw + v * 12 + axis * 4, value)
        native.call(0x45ab10, [UNIT])
        for number, piece in enumerate(pieces):
            runtime = MODEL + 0x1000 + number * 0x400 + 0x180
            piece['expected'] = [[signed(native.read(runtime + v * 12 + axis * 4)) for axis in range(3)] for v in range(len(piece['vertices']))]
        cases.append(dict(pieces=pieces, angles=angles))
    folder = Path('local/target-point')
    folder.mkdir(exist_ok=True)
    (folder / 'vertices.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_TARGET_VERTICES {len(cases)} trees')


if __name__ == '__main__':
    main()
