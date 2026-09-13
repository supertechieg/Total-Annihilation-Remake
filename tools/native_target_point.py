"""Run original 0x43e0b0 on supplied runtime vertices, including signed edges."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH
from cob import signed

MODEL, GEOMETRY, VERTICES, OUTPUT = 0x1500000, 0x1501000, 0x1502000, 0x1503000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(MODEL, 0x10000)
    native.write(UNIT + 0x9e, MODEL)
    rng = random.Random(0x43e0b0)
    cases = []
    edges = [0, 1, -1, 3, -3, 2147483647, -2147483648]
    for index in range(600):
        piece = index % 7
        vertices = [[rng.randint(-4000000, 4000000) for _ in range(3)] for _ in range(index % 17)]
        position = [rng.randint(-2147483648, 2147483647) for _ in range(3)]
        if index < len(edges):
            vertices = [[edges[index]] * 3]
            position = [0] * 3
        elif index < 100:
            vertices = [[rng.choice(edges) for _ in range(3)] for _ in range(index % 5)]
        record = MODEL + 0x22 + piece * 0x36
        native.write(record, GEOMETRY)
        native.write(record + 0x22, VERTICES)
        native.write(GEOMETRY + 4, len(vertices))
        for axis, value in enumerate(position):
            native.write(UNIT + 0x6a + axis * 4, value)
        for number, vertex in enumerate(vertices):
            for axis, value in enumerate(vertex):
                native.write(VERTICES + number * 12 + axis * 4, value)
        native.call(0x43e0b0, [UNIT, OUTPUT, piece])
        result = [signed(native.read(OUTPUT + axis * 4)) for axis in range(3)]
        cases.append(dict(vertices=vertices, position=position, piece=piece, expected=result))
    folder = Path('local/target-point')
    folder.mkdir(exist_ok=True)
    (folder / 'native.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_TARGET_POINT {len(cases)} cases')


if __name__ == '__main__':
    main()
