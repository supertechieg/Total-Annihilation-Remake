"""Original position-to-footprint conversion, spatial update callbacks stubbed."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    for callback in [0x47d0e0, 0x47cc30, 0x4827b0]:
        native.mu.mem_write(callback, b'\xc2\x04\x00')
    cases = []
    for size in [1, 2, 3, 4, 12]:
        for position in [-65537, -1, 0, 7 * 65536, 8 * 65536, 16 * 65536 - 1, 128 * 65536, 136 * 65536, 0x7fffffff, -0x80000000]:
            native.short(UNIT + 0x7e, size)
            native.short(UNIT + 0x80, size + 1)
            native.call(0x48a9f0, [UNIT, position & 0xffffffff, 0, position & 0xffffffff, 0])
            expected = list(struct.unpack('<hh', native.mu.mem_read(UNIT + 0x76, 4)))
            cases.append(dict(position=position, width=size, height=size + 1, expected=expected))
    Path('local/metal-maker/footprint.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_FOOTPRINT_ORIGIN {len(cases)} cases')


if __name__ == '__main__':
    main()
