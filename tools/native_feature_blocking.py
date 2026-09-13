"""Check original terrain predicate's feature flags and continuation cells."""
import json
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH
from feature_blocking import feature_blocking

# Supplied layouts on a 16x16 map: (x, z, footprintx, footprintz, blocking).
LAYOUTS = [
    [(3, 2, 4, 3, True)],
    [(3, 2, 4, 3, False)],
    [(0, 0, 3, 5, True), (6, 6, 2, 2, False), (10, 1, 5, 4, True)],
    [(12, 11, 4, 5, True), (0, 13, 1, 3, True), (5, 5, 1, 1, True)],
    [(1, 8, 12, 1, True), (7, 0, 1, 7, False), (8, 0, 8, 7, True)],
    [(2, 2, 9, 9, True)],
]


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    movement, cells, definitions = 0x1020000, 0x1030000, 0x1040000
    native.call(0x4402e0, [], this=movement)
    native.write(GAME + 0x14233, 16)
    native.write(GAME + 0x14253, 1)
    native.write(GAME + 0x1426f, definitions)
    native.mu.mem_write(GAME + 0x1427f, b'\0')
    differences = []
    count = 0
    for flags in [0, 1, 32, 64, 65, 128, 255]:
        native.mu.mem_write(definitions + 0xfe, bytes([flags]))
        for code in [0, 1, 0xfffb, 0xfffc, 0xfffd, 0xffff, 0xfffe]:
            native.mu.mem_write(cells, bytes(16 * 16 * 13))
            native.short(cells + 8, 0)
            cell = cells + (2 * 16 + 3) * 13
            native.short(cell + 8, code)
            native.mu.mem_write(cell + 10, bytes([2, 3]))
            actual = bool(native.call(0x47de60, [movement, cell]) & 255)
            expected = code == 0xffff or (code in (0, 0xfffe) and not flags & 64)
            count += 1
            if actual != expected:
                differences.append(dict(flags=flags, code=code, actual=actual, expected=expected))
    grid_cells = 0
    for layout_index, layout in enumerate(LAYOUTS):
        native.write(GAME + 0x14253, len(layout))
        data = bytearray(16 * 16 * 13)
        for i in range(16 * 16):
            data[i * 13 + 8:i * 13 + 10] = b'\xff\xff'
        for index, (x, z, width, height, blocking) in enumerate(layout):
            native.mu.mem_write(definitions + index * 0x100, bytes(0x100))
            # Unrelated flag bits must not affect the result.
            native.mu.mem_write(definitions + index * 0x100 + 0xfe, bytes([(0x40 if blocking else 0) | 0xa5 & ~0x40]))
            # Writes follow decompiled placement: anchor index, then 0xfffe with row offset +10, column offset +11.
            for dz in range(height):
                for dx in range(width):
                    at = ((z + dz) * 16 + x + dx) * 13
                    if dx == 0 and dz == 0:
                        data[at + 8:at + 10] = index.to_bytes(2, 'little')
                    else:
                        data[at + 8:at + 12] = bytes([0xfe, 0xff, dz, dx])
        native.mu.mem_write(cells, bytes(data))
        expected_grid = feature_blocking(16, 16, [dict(x=x, z=z, width=w, height=h, blocking=b) for x, z, w, h, b in layout])
        for i in range(16 * 16):
            actual = not bool(native.call(0x47de60, [movement, cells + i * 13]) & 255)
            grid_cells += 1
            if actual != bool(expected_grid[i]):
                differences.append(dict(layout=layout_index, cell=i, native_blocked=actual, reconstructed_blocked=bool(expected_grid[i])))
    Path('analysis/native-feature-blocking-validation.json').write_text(json.dumps(dict(
        cases=count, grid_cells=grid_cells, layouts=len(LAYOUTS), differences=differences, exe_sha256=EXE_HASH,
        scope='Original 0x47de60 feature branch on flat empty terrain; supplied feature flags, valid continuation offsets, invalid indices and sentinel codes; '
              'plus every cell of supplied multi-feature 16x16 layouts written as the decompiled placement loop does, compared with tools/feature_blocking.py; '
              'excludes executing original TNT loading, placement, overlap resolution and deletion'
    ), indent=2) + '\n', encoding='utf-8')
    print(f'FEATURE_BLOCKING {count + grid_cells - len(differences)} / {count + grid_cells} match ({count} predicate cases, {grid_cells} layout cells)')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
