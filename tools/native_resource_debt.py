"""Execute original per-unit energy/metal settlement with supplied fractions."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, UNIT
from native_cob_reference import EXE_HASH, STACK_TOP
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBX


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x401b9c, b'\xc3')
    cases = []
    fields = ['income', 'requested', 'accepted', 'debt', 'previous_income', 'previous_requested']
    for debt in [0, 0.1, 3, 60, 120]:
        for accepted in [0, 0.2, 20, 60]:
            for debt_fraction in [0, 0.1, 0.5, 1]:
                for accepted_fraction in [0, 0.3, 0.5, 1]:
                    for lane in [0, 1]:
                        # Different income/request sentinels also check the lane offsets.
                        for i, value in enumerate([12.5 + lane, 77.25 + lane, accepted, debt, -7, -9]):
                            native.mu.mem_write(UNIT + 0xbc + lane * 24 + i * 4, struct.pack('<f', value))
                        for offset, value in [(0x10, accepted_fraction), (0x30, debt_fraction)]:
                            native.mu.mem_write(STACK_TOP - 4 + offset + lane * 4, struct.pack('<f', value))
                    native.mu.reg_write(UC_X86_REG_EAX, UNIT + 0xc0)
                    native.mu.reg_write(UC_X86_REG_EBX, 0)
                    native.call(0x401b42, [])
                    for lane in [0, 1]:
                        values = struct.unpack('<6f', native.mu.mem_read(UNIT + 0xbc + lane * 24, 24))
                        cases.append(dict(lane=lane, income=12.5 + lane, requested=77.25 + lane,
                                          accepted=accepted, debt=debt, debt_fraction=debt_fraction,
                                          accepted_fraction=accepted_fraction, expected=dict(zip(fields, values))))
    Path('local/metal-maker/debt.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_RESOURCE_DEBT {len(cases)} cases')


if __name__ == '__main__':
    main()
