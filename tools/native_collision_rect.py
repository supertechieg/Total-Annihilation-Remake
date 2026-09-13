"""Original unit creation position-to-cell rectangle arithmetic."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH, STACK_TOP
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EDI, UC_X86_REG_ESI


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x485bd6, b'\xc3')
    rng = random.Random(1957)
    cases = []
    for index in range(600):
        footprint = [rng.randrange(1, 9), rng.randrange(1, 9)]
        position = [rng.randrange(-2147483648, 2147483648), rng.randrange(-2147483648, 2147483648)]
        if index < 120:
            # One raw unit either side of footprint-adjusted cell boundaries.
            position = [rng.randrange(-4, 10) * 1048576 + (size - 1) * 524288 + (index % 3 - 1) for size in footprint]
        native.mu.reg_write(UC_X86_REG_EAX, position[0] & 0xffffffff)
        native.mu.reg_write(UC_X86_REG_EDI, footprint[0])
        native.mu.reg_write(UC_X86_REG_ESI, UNIT)
        native.short(STACK_TOP - 4 + 0x22, footprint[1])
        native.call(0x485ba0, [], this=position[1] & 0xffffffff)
        expected = list(struct.unpack('<hh', native.mu.mem_read(UNIT + 0x76, 4)))
        cases.append(dict(position=position, footprint=footprint, expected=expected))
    folder = Path('local/collision')
    folder.mkdir(exist_ok=True)
    (folder / 'native-rect.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_COLLISION_RECT {len(cases)} cases')


if __name__ == '__main__':
    main()
