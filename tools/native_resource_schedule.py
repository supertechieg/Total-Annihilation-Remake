"""Original economy deadline gate, before player/session eligibility checks."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH
from unicorn.x86_const import UC_X86_REG_EDI


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    player = 0x100a000
    for stop in [0x465098, 0x4655a6]:
        native.mu.mem_write(stop, b'\xc3')
    cases = []
    values = [0, 1, 29, 30, 31, 60, 300, 0x7fffffff, 0xffffffe2, 0xffffffff]
    for tick in values:
        for deadline in values:
            native.mu.mem_write(GAME + 0x38a47, struct.pack('<I', tick))
            native.mu.mem_write(player + 0xf0, struct.pack('<I', deadline))
            native.mu.reg_write(UC_X86_REG_EDI, player)
            native.call(0x465077, [])
            updated = struct.unpack('<I', native.mu.mem_read(player + 0xf0, 4))[0]
            cases.append(dict(tick=tick, deadline=deadline, expected=dict(due=updated != deadline, deadline=updated)))
    Path('local/metal-maker/schedule.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_RESOURCE_SCHEDULE {len(cases)} cases')


if __name__ == '__main__':
    main()
