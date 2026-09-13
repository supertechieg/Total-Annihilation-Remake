"""Original endpoint cell lookup and unit-slot collision, without terrain/features."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH

GRID, UNITS, PROJECTILE, OUTPUT = 0x1009000, 0x100a000, 0x100b000, 0x100c000
DEFS = 0x100d000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    # Capture target pointer at impact dispatch; retain all lookup/selection code.
    native.mu.mem_write(0x499eb0, b'\x8b\x44\x24\x08\xa3' + struct.pack('<I', OUTPUT) + b'\xc2\x08\x00')
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
    folder = Path('local/collision')
    folder.mkdir(exist_ok=True)
    (folder / 'native-projectile.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_PROJECTILE_COLLISION {len(cases)} cases')


if __name__ == '__main__':
    main()
