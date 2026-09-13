"""Original movement-cell predicate with no feature or occupying unit."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    movement, cell = 0x1020000, 0x1030000
    native.mu.mem_write(cell, bytes(13))
    native.short(cell + 8, 0xffff)
    rng = random.Random(47)
    cases = []
    for index in range(1000):
        sea = rng.choice([0, 16, 32, 128, 255])
        low = rng.randrange(256)
        high = rng.randrange(low, 256)
        maximum = rng.choice([0, 12, 32, 100, 10000])
        minimum = rng.choice([-10000, 0, 3, 15, 32])
        slope = rng.choice([0, 12, 32, 255])
        water_slope = rng.choice([0, 30, 255])
        native.short(movement + 8, maximum)
        native.short(movement + 10, minimum)
        native.mu.mem_write(movement + 12, bytes([slope, slope >> 1, water_slope, water_slope >> 1]))
        native.mu.mem_write(GAME + 0x1427f, bytes([sea]))
        native.mu.mem_write(cell + 5, bytes([high, low]))
        result = native.call(0x47de60, [movement, cell]) & 255
        cases.append(dict(sea=sea, low=low, high=high, maximum=maximum, minimum=minimum,
                          slope=slope, water_slope=water_slope, expected=bool(result)))
    folder = Path('local/terrain-limits')
    folder.mkdir(exist_ok=True)
    (folder / 'native.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'TERRAIN_LIMITS recorded {len(cases)} original cell decisions')


if __name__ == '__main__':
    main()
