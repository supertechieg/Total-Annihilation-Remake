"""Execute original full-map height extrema update with supplied vertex grids."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH
from terrain_heights import cell_extrema


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    address = 0x1020000
    rng = random.Random(483210)
    differences = []
    count = 0
    for case in range(50):
        width, height = rng.randrange(2, 32), rng.randrange(2, 32)
        heights = bytes(rng.randrange(256) for _ in range(width * height))
        data = bytearray(width * height * 13)
        for index, value in enumerate(heights):
            data[index * 13 + 4] = value
        native.mu.mem_write(address, bytes(data))
        native.write(GAME + 0x14287, address)
        native.write(GAME + 0x14233, width)
        native.write(GAME + 0x14237, height)
        native.call(0x483210, [0, width | (height << 16)])
        result = bytes(native.mu.mem_read(address, len(data)))
        low, high = cell_extrema(heights, width, height)
        for index in range(width * height):
            count += 1
            if (low[index], high[index]) != (result[index * 13 + 6], result[index * 13 + 5]):
                differences.append(dict(case=case, index=index))
    Path('analysis/native-terrain-heights-validation.json').write_text(json.dumps(dict(
        maps=50, cells=count, differences=differences, exe_sha256=EXE_HASH,
        scope='Original 0x483210 full-map rectangle with supplied height bytes and zero-initialized output; excludes partial updates, TNT decoding, boundary feature blocking and navigation'
    ), indent=2) + '\n', encoding='utf-8')
    print(f'TERRAIN_HEIGHTS {count - len(differences)} / {count} cells match')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
