"""Original whole movement-map build for Boolean terrain cells and footprints."""
import json
import random
import struct
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    movement, cells, output, scratch = 0x1020000, 0x1030000, 0x1040000, 0x1050000
    native.mu.mem_write(0x4b4f10, b'\xb8' + struct.pack('<I', scratch) + b'\xc3')
    native.mu.mem_write(0x4b4f20, b'\xc3')
    native.write(GAME + 0x14287, cells)
    native.mu.mem_write(GAME + 0x1427f, b'\0')
    rng = random.Random(440500)
    differences = []
    checked = 0
    for case in range(60):
        width, height = 24, 24
        fx, fz = 1 + case % 6, 1 + (case // 6) % 6
        allowed = [rng.random() > (0.0 if case < 6 else 0.08) for _ in range(width * height)]
        raw = bytearray(width * height * 13)
        for index, value in enumerate(allowed):
            raw[index * 13 + 5] = 0 if value else 100
            struct.pack_into('<H', raw, index * 13 + 8, 0xffff)
        native.mu.mem_write(cells, bytes(raw))
        native.call(0x4402e0, [], this=movement)
        native.short(movement + 4, fx)
        native.short(movement + 6, fz)
        native.mu.mem_write(movement + 12, bytes([20, 10, 255, 127]))
        native.write(movement + 16, width)
        native.write(movement + 20, height)
        native.write(movement + 24, output)
        native.mu.mem_write(output, bytes(width * ((height + 15) // 16) * 4))
        native.call(0x440500, [], this=movement)
        for y in range(height):
            for x in range(width):
                word = native.read(output + ((y >> 4) * width + x) * 4)
                actual = (word >> ((y & 15) * 2)) & 3
                expected = int(x + fx <= width and y + fz <= height and all(
                    allowed[yy * width + xx] for yy in range(y, min(y + fz, height))
                    for xx in range(x, min(x + fx, width))))
                if expected and x > 0 and y > 0 and x + fx < width and y + fz < height and all(
                    allowed[yy * width + xx] for yy in range(y - 1, y + fz + 1)
                    for xx in range(x - 1, x + fx + 1)):
                    expected = 3
                checked += 1
                if actual != expected:
                    differences.append(dict(case=case, x=x, y=y, actual=actual, expected=expected))
    Path('analysis/native-footprint-passability-validation.json').write_text(json.dumps(dict(
        maps=60, cells=checked, differences=differences, exe_sha256=EXE_HASH,
        scope='Original 0x440500 plus original cell predicate on unoccupied feature-free Boolean terrain; allocator/free stubbed; footprints 1 to 6; excludes query-to-unit coordinate mapping and dynamic updates'
    ), indent=2) + '\n', encoding='utf-8')
    print(f'FOOTPRINT_PASSABILITY {checked - len(differences)} / {checked} cells match')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
