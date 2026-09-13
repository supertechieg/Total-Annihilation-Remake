"""Original two-stage resource allocation loop with supplied aggregate totals."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH, STACK_TOP
from unicorn.x86_const import UC_X86_REG_ESI


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x401ab3, b'\xc3')
    sp = STACK_TOP - 4
    cases = []
    for available in [0, 0.1, 1, 10, 60, 100, 1000]:
        for debt in [0, 0.3, 3, 60, 120]:
            for accepted in [0, 0.2, 20, 60, 200]:
                for axis in [0, 4]:
                    for offset, value in [(0x18, debt), (0x20, accepted), (0x28, available)]:
                        native.mu.mem_write(sp + offset + axis, struct.pack('<f', value))
                native.mu.reg_write(UC_X86_REG_ESI, 0x3f800000)
                native.call(0x401a4d, [], this=0)
                read = lambda offset: struct.unpack('<f', native.mu.mem_read(sp + offset, 4))[0]
                for axis in [0, 4]:
                    cases.append(dict(axis=axis, available=available, debt=debt, accepted=accepted,
                                      expected=dict(remaining=read(0x28 + axis), debt_fraction=read(0x30 + axis), accepted_fraction=read(0x10 + axis))))
    Path('local/metal-maker/allocation.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_RESOURCE_ALLOCATION {len(cases)} cases')


if __name__ == '__main__':
    main()
