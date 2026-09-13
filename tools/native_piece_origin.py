"""Run original piece-origin traversal with synthetic model/pose records."""
import json
from pathlib import Path
import random
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH
from cob import signed

MODEL, GEOMETRY, OUTPUT = 0x100a000, 0x100c000, 0x100b000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    rng = random.Random(1952)
    cases = []
    for index in range(600):
        pieces = []
        for piece in range(1 + index % 6):
            pieces.append(dict(parent=-1 if piece == 0 else rng.randrange(piece),
                               offset=[rng.randrange(-1000000, 1000001) for _ in range(3)],
                               move=[rng.randrange(-65536, 65537) for _ in range(3)],
                               rotation=[rng.randrange(65536) for _ in range(3)]))
        angles = [rng.randrange(65536) for _ in range(3)]  # roll, heading, pitch
        target = index % len(pieces)
        native.write(UNIT + 0x9e, MODEL)
        native.write(MODEL, len(pieces))
        for axis in range(3):
            native.short(UNIT + 0x64 + axis * 2, angles[axis])
        for number, piece in enumerate(pieces):
            record = MODEL + 0x22 + number * 0x36
            geom = GEOMETRY + number * 0x40
            native.write(record, geom)
            native.write(record + 0x32, 0 if piece['parent'] < 0 else MODEL + 0x22 + piece['parent'] * 0x36)
            for axis in range(3):
                native.write(geom + 0x10 + axis * 4, piece['offset'][axis])
                native.write(record + 4 + axis * 4, piece['move'][axis])
                native.short(record + 0x10 + axis * 2, piece['rotation'][axis])
        native.call(0x43def0, [OUTPUT, UNIT, target])
        cases.append(dict(pieces=pieces, angles=angles, target=target,
                          expected=[signed(native.read(OUTPUT + axis * 4)) for axis in range(3)]))
    folder = Path('local/piece-origin')
    folder.mkdir(exist_ok=True)
    (folder / 'native-origins.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_PIECE_ORIGIN {len(cases)} cases')


if __name__ == '__main__':
    main()
