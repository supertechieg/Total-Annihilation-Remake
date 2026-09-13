"""Original ballistic timer branch, capturing expiry versus live integration."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESI, UC_X86_REG_EBP, UC_X86_REG_EDI

PROJECTILE, EVENT = 0x100a000, 0x100b000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x49bd86, b'\xc3')
    native.mu.mem_write(0x49bd8d, b'\xc3')
    # Impact and expiration visual notifications are captured, not simulated.
    for address, event in [(0x499eb0, 2), (0x472810, 1)]:
        native.mu.mem_write(address, b'\xc7\x05' + struct.pack('<II', EVENT, event) + b'\xc2\x08\x00')
    rng = random.Random(1958)
    cases = []
    for index in range(600):
        tick = rng.randrange(0x100000000)
        deadline = [tick, (tick - 1) & 0xffffffff, (tick + 1) & 0xffffffff, 0, 0xffffffff][index % 5]
        timer = [0, 1, 30, 65535][index % 4]
        burnblow = bool((index // 4) % 2)
        position = [rng.randrange(-10000000, 10000000) for _ in range(3)]
        velocity = [rng.randrange(-1000000, 1000000) for _ in range(3)]
        flags = 2 | (0x800000 if burnblow else 0)
        native.mu.mem_write(PROJECTILE, bytes(0x6b))
        native.write(PROJECTILE, DEFINITION)
        native.write(DEFINITION + 0x111, flags)
        native.short(DEFINITION + 0xe6, timer)
        native.write(PROJECTILE + 0x46, deadline)
        native.write(GAME + 0x38a47, tick)
        native.write(GAME + 0x14263, 4369)
        native.write(EVENT, 0)
        for axis in range(3):
            native.write(PROJECTILE + 4 + axis * 4, position[axis])
            native.write(PROJECTILE + 0x1c + axis * 4, velocity[axis])
            native.write(GAME + 0x37ecc + axis * 4, 0)
        native.mu.reg_write(UC_X86_REG_EAX, flags)
        native.mu.reg_write(UC_X86_REG_ESI, DEFINITION)
        native.mu.reg_write(UC_X86_REG_EBP, PROJECTILE)
        native.mu.reg_write(UC_X86_REG_EDI, 0)
        native.call(0x49bb60, [])
        cases.append(dict(tick=tick, deadline=deadline, timer=timer, burnblow=burnblow,
                          position=position, velocity=velocity, event=native.read(EVENT),
                          expected_position=[signed(native.read(PROJECTILE + 4 + axis * 4)) for axis in range(3)],
                          expected_velocity=[signed(native.read(PROJECTILE + 0x1c + axis * 4)) for axis in range(3)]))
    folder = Path('local/ballistics')
    (folder / 'native-lifetime.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_BALLISTIC_LIFETIME {len(cases)} cases')


if __name__ == '__main__':
    main()
