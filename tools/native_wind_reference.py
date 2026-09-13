"""Execute original wind update and RNGs with a synthetic CRT thread record."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH
from cob import signed

THREAD = 0x100b000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    # Only CRT thread-local storage lookup is replaced. Both random algorithms,
    # bounded sampling, original trig helpers and wind update run unchanged.
    native.mu.mem_write(0x4eb0f0, b'\xb8' + struct.pack('<I', THREAD) + b'\xc3')
    rng = random.Random(1951)
    cases = []
    for index in range(600):
        case = dict(tick=[1000, 100, 99][index % 3], next_tick=100,
                    minimum=[0, 100, 1000][index % 3], maximum=[0, 101, 2000][index % 3],
                    normalization=1000, strength=100, heading=rng.randrange(65536),
                    drift=[12, 34, 56], ratio=0.5,
                    crt_seed=rng.randrange(0x100000000), game_seed=rng.randrange(1, 2147483647))
        # Ensure both calm and non-calm updates, plus unchanged/equal timer states.
        if index % 7 == 0:
            case['tick'] = 1000
        for field, offset in [('tick', 0x38a47), ('next_tick', 0x37ec4), ('minimum', 0x1425b),
                              ('maximum', 0x1425f), ('normalization', 0x37ec8), ('strength', 0x37eda)]:
            native.write(GAME + offset, case[field])
        native.short(GAME + 0x37ed8, case['heading'])
        for axis in range(3):
            native.write(GAME + 0x37ecc + axis * 4, case['drift'][axis])
        native.mu.mem_write(GAME + 0x37ede, struct.pack('<f', case['ratio']))
        native.write(THREAD + 0x14, case['crt_seed'])
        native.write(0x51fc88, case['game_seed'])
        native.call(0x490c40, [])
        case['expected'] = dict(next_tick=native.read(GAME + 0x37ec4), strength=signed(native.read(GAME + 0x37eda)),
                                heading=native.read(GAME + 0x37ed8) & 65535,
                                drift=[signed(native.read(GAME + 0x37ecc + axis * 4)) for axis in range(3)],
                                ratio=struct.unpack('<f', native.mu.mem_read(GAME + 0x37ede, 4))[0],
                                changed=native.read(GAME + 0x37ee2), crt_seed=native.read(THREAD + 0x14),
                                game_seed=native.read(0x51fc88))
        cases.append(case)
    folder = Path('local/wind')
    folder.mkdir(exist_ok=True)
    (folder / 'native-wind.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_WIND_REFERENCE {len(cases)} cases')


if __name__ == '__main__':
    main()
