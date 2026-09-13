"""Run original ordinary-unit and yard-map grid insertion, movement and removal."""
import json
from pathlib import Path
import random
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH

GRID, UNITS, CONTROLLERS, COARSE = 0x1009000, 0x100a000, 0x100b000, 0x100c000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    # Downstream overlap notifications and visibility refresh are outside scope.
    native.mu.mem_write(0x47e5c0, b'\xc2\x0c\x00')
    native.mu.mem_write(0x440a70, b'\xc2\x04\x00')
    native.mu.mem_write(0x483210, b'\xc2\x08\x00')
    native.mu.mem_write(0x440a40, b'\xc2\x08\x00')
    native.mu.mem_write(0x4827b0, b'\xc2\x04\x00')
    for offset, value in [(0x14233, 8), (0x14237, 8), (0x14287, GRID),
                          (0x14357, UNITS), (0x1429f, COARSE), (0x142a3, 1), (0x142b7, COARSE + 32)]:
        native.write(GAME + offset, value)
    rng = random.Random(1956)
    cases = []

    def snapshot():
        return dict(cells=[[native.read(GRID + i * 13) & 65535,
                            native.read(GRID + i * 13 + 2) & 65535] for i in range(64)],
                    flags=[native.read(UNITS + i * 0x118 + 0x110) for i in range(1, 4)])

    def full_snapshot():
        result = snapshot()
        result['terrain_flags'] = [native.mu.mem_read(GRID + i * 13 + 12, 1)[0] for i in range(64)]
        return result

    for index in range(600):
        x, z = rng.randrange(7), rng.randrange(7)
        width, depth = rng.randrange(1, 4), rng.randrange(1, 4)
        slot = index % 2
        replacement = [False, bool(index % 3), bool(index % 4)]
        cells = [[rng.choice([0, 0, 2, 3]), rng.choice([0, 0, 2, 3])] for _ in range(64)]
        yard = [rng.choice([0, 0x35, 0x8f, 0x2b, 0x31, 0x2d, 0x6f, 0x2f, 0x37, 0x29]) for _ in range(width * depth)] if index >= 300 else []
        yard_open = bool(index % 2)
        terrain_flags = [rng.randrange(256) for _ in range(64)]
        for i, cell in enumerate(cells):
            native.short(GRID + i * 13, cell[0])
            native.short(GRID + i * 13 + 2, cell[1])
            native.mu.mem_write(GRID + i * 13 + 12, bytes([terrain_flags[i]]))
        for i in range(1, 4):
            unit = UNITS + i * 0x118
            native.mu.mem_write(unit, bytes(0x118))
            native.short(unit + 0xa8, i)
            native.write(unit + 0x96, CONTROLLERS + i * 0x100)
            native.write(CONTROLLERS + i * 0x100, 1 if replacement[i - 1] else 0)
            native.mu.mem_write(CONTROLLERS + i * 0x100 + 0x73, b'\x03')
        unit = UNITS + 0x118
        initial_flags = (slot + 1) | (0x20000000 if yard else 0)
        native.write(unit + 0x110, initial_flags)
        native.write(unit + 0x92, 0x100d000)
        native.write(0x100d000 + 0x14e, 0x100e000)
        native.mu.mem_write(0x100e000, bytes(yard or [0]))
        native.mu.mem_write(unit + 0x10f, bytes([4 if yard_open else 0]))
        native.short(unit + 0x76, x)
        native.short(unit + 0x78, z)
        native.short(unit + 0x7e, width)
        native.short(unit + 0x80, depth)
        native.write(unit + 0x82, COARSE)
        native.write(unit + 0x86, 1)  # Coarse-list linking deliberately suppressed.
        native.call(0x47cc30, [unit])
        inserted = full_snapshot()
        # Exercise unchanged rectangles, cell crossings and slot transitions.
        next_x, next_z = (x, z) if index % 3 == 0 else (rng.randrange(-1, 8), rng.randrange(-1, 8))
        next_slot = slot if index % 3 != 2 else 1 - slot
        position = [next_x * 1048576 + (width - 1) * 524288 + 1,
                    rng.randrange(-5, 25) * 65536,
                    next_z * 1048576 + (depth - 1) * 524288 + 1]
        native.call(0x48a9f0, [unit, *position, next_slot + 1])
        moved = full_snapshot()
        moved['position'] = [native.read(unit + offset) for offset in (0x6a, 0x6e, 0x72)]
        moved['origin'] = [native.read(unit + offset) & 65535 for offset in (0x76, 0x78)]
        native.call(0x47d0e0, [unit])
        cases.append(dict(x=x, z=z, width=width, depth=depth, slot=slot,
                          replacement=replacement, cells=cells, yard=yard, yard_open=yard_open,
                          terrain_flags=terrain_flags, initial_flags=initial_flags,
                          position=position, next_slot=next_slot,
                          inserted=inserted, moved=moved, removed=full_snapshot()))
    folder = Path('local/collision')
    folder.mkdir(exist_ok=True)
    (folder / 'native-grid.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_COLLISION_GRID {len(cases)} insert/move/remove cases')


if __name__ == '__main__':
    main()
