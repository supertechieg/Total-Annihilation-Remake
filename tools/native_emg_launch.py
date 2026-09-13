"""Original direct projectile launch angles and velocity, with acceleration disabled."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, DEFINITION
from native_cob_reference import EXE_HASH, STACK_TOP
from cob import signed
from unicorn.x86_const import UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBX

SOURCE, TARGET, PROJECTILE, CONTROLLER = 0x100a000, 0x100a020, 0x100b000, 0x100c000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x49cb1c, b'\xc3')
    native.write(CONTROLLER + 0xc, DEFINITION)
    native.write(PROJECTILE, DEFINITION)
    native.write(DEFINITION + 0x6c, 0)
    native.write(DEFINITION + 0x70, 0)
    rng = random.Random(0x49ca37)
    cases = []
    for index in range(240):
        source = [rng.randint(-10000000, 10000000) for _ in range(3)]
        target = [rng.randint(-10000000, 10000000) for _ in range(3)]
        speed = [655359, 371370, 458751][index % 3]
        if index < 6:
            source = [0, 0, 0]
            target = [[65536, 0, 0], [0, 65536, 0], [0, 0, 65536], [-65536, 0, 0], [0, -65536, 0], [0, 0, 0]][index]
        native.write(DEFINITION + 0x68, speed)
        for axis in range(3):
            native.write(SOURCE + axis * 4, source[axis])
            native.write(TARGET + axis * 4, target[axis])
        native.write(STACK_TOP - 4 + 0x1c, SOURCE)
        native.mu.reg_write(UC_X86_REG_ESI, PROJECTILE)
        native.mu.reg_write(UC_X86_REG_EDI, CONTROLLER)
        native.mu.reg_write(UC_X86_REG_EBX, TARGET)
        native.call(0x49ca37, [])
        cases.append(dict(source=source, target=target, speed=speed, expected=dict(
            heading=native.read(PROJECTILE + 0x36) & 65535, pitch=native.read(PROJECTILE + 0x38) & 65535,
            distance=native.read(PROJECTILE + 0x3e), velocity=[signed(native.read(PROJECTILE + 0x1c + axis * 4)) for axis in range(3)])))
    Path('local/ballistics/emg-launch.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_EMG_LAUNCH {len(cases)} cases')


if __name__ == '__main__':
    main()
