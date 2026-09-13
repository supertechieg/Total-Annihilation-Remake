"""Original nonnegative upkeep gate, isolated from resource settlement."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH
from unicorn.x86_const import UC_X86_REG_ESI, UC_X86_REG_EDX


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    stub, value = 0x1008000, 0x1009000
    native.mu.mem_write(stub, b'\xd9\x05' + struct.pack('<I', value) + b'\xe9' + struct.pack('<i', 0x4013eb - (stub + 11)))
    native.mu.mem_write(0x401480, b'\xc3')
    cases = []
    for upkeep in [0.0, 3.0, 60.0, 0.1]:
        for debt in [-1.0, 0.0, 0.0001, 60.0]:
            for requested, accepted in [(0.0, 0.0), (12.5, 7.25)]:
                for address, scalar in [(value, upkeep), (UNIT + 0xc0, requested), (UNIT + 0xc4, accepted), (UNIT + 0xc8, debt)]:
                    native.mu.mem_write(address, struct.pack('<f', scalar))
                native.mu.reg_write(UC_X86_REG_ESI, UNIT)
                native.call(stub, [])
                read = lambda offset: struct.unpack('<f', native.mu.mem_read(UNIT + offset, 4))[0]
                cases.append(dict(upkeep=upkeep, debt=debt, requested=requested, accepted=accepted,
                                  expected=dict(requested=read(0xc0), accepted=read(0xc4), productive=native.mu.reg_read(UC_X86_REG_EDX))))
    Path('local/metal-maker/upkeep.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_UPKEEP_GATE {len(cases)} cases')


if __name__ == '__main__':
    main()
