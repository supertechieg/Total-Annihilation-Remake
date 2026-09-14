"""Original endpoint cell lookup, unit-slot collision and the terrain/feature/water branch of 0x49b090."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed

GRID, UNITS, PROJECTILE, OUTPUT = 0x1009000, 0x100a000, 0x100b000, 0x100c000
DEFS = 0x100d000
FEATURES, MAP = 0x1010000, 0x1012000
TERRAIN_SIZE = 8


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    # Capture target pointer and count impact dispatches; retain all lookup/selection code.
    native.mu.mem_write(0x499eb0, b'\x8b\x44\x24\x08\xa3' + struct.pack('<I', OUTPUT) + b'\xff\x05' + struct.pack('<I', OUTPUT + 4) + b'\xc2\x08\x00')
    native.write(GAME + 0x14233, 4)
    native.write(GAME + 0x14237, 4)
    native.write(GAME + 0x14287, GRID)
    native.write(GAME + 0x14357, UNITS)
    native.write(DEFINITION + 0x111, 0x4000)  # Skip terrain/feature collision only.
    rng = random.Random(1955)
    cases = []
    for index in range(600):
        position = [rng.randrange(-65536, 65 * 65536), rng.randrange(-10, 50) * 65536,
                    rng.randrange(-65536, 65 * 65536)]
        owner = index % 3
        occupants = []
        for slot in range(2):
            bottom = rng.randrange(-10, 10) * 65536
            top = bottom + rng.randrange(1, 40) * 65536
            occupants.append(dict(id=slot + 1 if rng.randrange(4) else 0,
                                  owner=rng.randrange(3), bottom=bottom, top=top))
        if index % 4 == 0:
            position[1] = occupants[index % 2]['top']
        elif index % 4 == 1:
            position[1] = occupants[1]['bottom']
        native.mu.mem_write(PROJECTILE, bytes(0x80))
        native.write(PROJECTILE, DEFINITION)
        native.mu.mem_write(PROJECTILE + 0x66, bytes([owner]))
        for axis, value in enumerate(position):
            native.write(PROJECTILE + 4 + 4 * axis, value)
        for cell in range(16):
            native.short(GRID + cell * 13, occupants[0]['id'])
            native.short(GRID + cell * 13 + 2, occupants[1]['id'])
        for slot, occupant in enumerate(occupants):
            unit = UNITS + (slot + 1) * 0x118
            definition = DEFS + slot * 0x300
            native.write(unit + 0x92, definition)
            native.write(unit + 0x6e, 0)
            native.mu.mem_write(unit + 0xff, bytes([occupant['owner']]))
            native.write(definition + 0x162, occupant['bottom'])
            native.write(definition + 0x16e, occupant['top'])
        native.write(OUTPUT, 0)
        cell = native.call(0x4815a0, [PROJECTILE + 4])
        native.call(0x49b090, [DEFINITION, PROJECTILE])
        target = native.read(OUTPUT)
        cases.append(dict(position=position, owner=owner, occupants=occupants,
                          cell=(cell - GRID) // 13 if cell else -1,
                          target=(target - UNITS) // 0x118 if target else 0,
                          expired=bool(native.mu.mem_read(PROJECTILE + 0x69, 1)[0] & 2)))
    terrain_cases = terrain(native)
    folder = Path('local/collision')
    folder.mkdir(exist_ok=True)
    (folder / 'native-projectile.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases, terrain_cases=terrain_cases)))
    print(f'NATIVE_PROJECTILE_COLLISION {len(cases)} unit cases, {len(terrain_cases)} terrain cases')


def terrain(native):
    """Empty unit slots so every case reaches the terrain, feature and water tests."""
    native.write(GAME + 0x14233, TERRAIN_SIZE)
    native.write(GAME + 0x14237, TERRAIN_SIZE)
    native.write(GAME + 0x14287, GRID)
    native.write(GAME + 0x1426f, FEATURES)
    native.write(GAME + 0x391e9, MAP)
    rng = random.Random(0x49b31b)
    cases = []
    for index in range(1200):
        flags = [0, 0x4000, 0x8000, 0x10000, 0x18000, 0x8001, 1, 0x14000][index % 8]
        cells = []
        for _ in range(TERRAIN_SIZE * TERRAIN_SIZE):
            low = rng.randrange(256)
            cells.append(dict(low=low, high=rng.randrange(low, 256), code=0xffff, dz=0, dx=0))
        x, z = rng.randrange(TERRAIN_SIZE), rng.randrange(TERRAIN_SIZE)
        cell = cells[z * TERRAIN_SIZE + x]
        feature_count = rng.randrange(1, 4)
        feature_heights = [rng.randrange(0, 41) for _ in range(4)]
        mode = (index // 8) % 7
        if mode == 1:
            cell['code'] = rng.randrange(feature_count)
        elif mode == 2:
            cell['code'] = feature_count + rng.randrange(2)  # beyond the loaded feature count
        elif mode == 3:
            cell['code'] = [0xfffb, 0xfffc, 0xfffd][index % 3]
        elif mode >= 4:
            cell['dz'], cell['dx'] = rng.randrange(z + 1), rng.randrange(x + 1)
            anchor = cells[(z - cell['dz']) * TERRAIN_SIZE + x - cell['dx']]
            if cell['dz'] or cell['dx']:
                # Redirected anchors are not bounds-checked against the feature count.
                anchor['code'] = [rng.randrange(feature_count), 0xffff, 0xfffd, 3][mode - 4 if mode < 7 else 3]
            cell['code'] = 0xfffe
        top = cell['low'] + (feature_heights[cell['code']] if cell['code'] < 4 else 0)
        base = [cell['low'], top, rng.randrange(-5, 300)][index % 3]
        y = (base + rng.randrange(-2, 3)) * 65536 + rng.randrange(65536)
        position = [x * 16 * 65536 + rng.randrange(16 * 65536), y, z * 16 * 65536 + rng.randrange(16 * 65536)]
        velocity_y = rng.randrange(-2000000, 2000000)
        sea = [0, cell['low'], min(255, cell['low'] + 1), 255, rng.randrange(256)][(index // 5) % 5]
        lava = int(index % 13 == 6)
        cache_x, cache_z = (position[0] >> 16) // 16, (position[2] >> 16) // 16
        if index % 4 != 1:
            cache_x, cache_z = rng.randrange(-3, TERRAIN_SIZE + 3), rng.randrange(-3, TERRAIN_SIZE + 3)
        data = bytearray(TERRAIN_SIZE * TERRAIN_SIZE * 13)
        for i, item in enumerate(cells):
            data[i * 13 + 5] = item['high']
            data[i * 13 + 6] = item['low']
            data[i * 13 + 8:i * 13 + 10] = item['code'].to_bytes(2, 'little')
            data[i * 13 + 10] = item['dz']
            data[i * 13 + 11] = item['dx']
        native.mu.mem_write(GRID, bytes(data))
        native.write(GAME + 0x14253, feature_count)
        for i, value in enumerate(feature_heights):
            native.mu.mem_write(FEATURES + i * 0x100 + 0xfa, bytes([value]))
        native.mu.mem_write(GAME + 0x1427f, bytes([sea]))
        native.write(MAP + 0xd48, lava)
        native.write(DEFINITION + 0x111, flags)
        native.mu.mem_write(PROJECTILE, bytes(0x80))
        native.write(PROJECTILE, DEFINITION)
        for axis, value in enumerate(position):
            native.write(PROJECTILE + 4 + 4 * axis, value & 0xffffffff)
        native.write(PROJECTILE + 0x20, velocity_y & 0xffffffff)
        native.short(PROJECTILE + 0x5a, cache_x & 0xffff)
        native.short(PROJECTILE + 0x5c, cache_z & 0xffff)
        native.write(OUTPUT, 0)
        native.write(OUTPUT + 4, 0)
        native.call(0x49b090, [DEFINITION, PROJECTILE])
        cases.append(dict(flags=flags, cell=cell, anchor_code=cells[(z - cell['dz']) * TERRAIN_SIZE + x - cell['dx']]['code'],
                          feature_count=feature_count, feature_heights=feature_heights, sea=sea, lava=lava,
                          position=position, velocity_y=velocity_y, cache=[cache_x, cache_z],
                          expected=dict(impacts=native.read(OUTPUT + 4), velocity_y=signed(native.read(PROJECTILE + 0x20)),
                                        cache=[signed16(native.read(PROJECTILE + 0x5a) & 0xffff), signed16(native.read(PROJECTILE + 0x5c) & 0xffff)],
                                        surface=native.read(PROJECTILE + 0x5e) & 0xffff,
                                        removed=bool(native.mu.mem_read(PROJECTILE + 0x69, 1)[0] & 2))))
    return cases


def signed16(value):
    return value - 0x10000 if value >= 0x8000 else value


if __name__ == '__main__':
    main()
