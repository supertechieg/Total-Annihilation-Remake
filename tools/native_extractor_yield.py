"""Original extractor yield and map lookup with supplied 13-byte map cells."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, UNIT, DEFINITION, GAME
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    cells = 0x1020000
    native.write(GAME + 0x14233, 32)
    native.write(GAME + 0x14237, 32)
    native.write(GAME + 0x14287, cells)
    native.write(UNIT + 0x9a, 0)  # Script callback outside this fixture.
    cases = []
    for pattern in [0, 1, 127, 255, -1]:
        metal = [((i * 73 + 19) & 255) if pattern == -1 else pattern for i in range(1024)]
        for i, value in enumerate(metal):
            native.mu.mem_write(cells + i * 13 + 7, bytes([value]))
        for x, z, width, height in [(0, 0, 2, 2), (7, 9, 3, 4), (-1, -1, 2, 2), (31, 31, 3, 3), (40, 40, 2, 2), (0, 0, 16, 16), (0, 0, 32, 32), (0, 0, 0, 2)]:
            for scale in [0, -0.1, 0.001, 0.01]:
                for offset, value in [(0x76, x), (0x78, z), (0x7e, width), (0x80, height)]:
                    native.short(UNIT + offset, value)
                native.mu.mem_write(DEFINITION + 0x1ce, struct.pack('<f', scale))
                native.mu.mem_write(UNIT + 0x58, struct.pack('<f', 7.25))
                native.call(0x437840, [UNIT])
                result = struct.unpack('<f', native.mu.mem_read(UNIT + 0x58, 4))[0]
                cases.append(dict(pattern=pattern, x=x, z=z, width=width, height=height, scale=scale, previous=7.25, expected=result))
    Path('local/metal-maker/extractor.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_EXTRACTOR_YIELD {len(cases)} cases')


if __name__ == '__main__':
    main()
