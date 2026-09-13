"""Original ballistic launch velocity block with supplied controller state."""
import json
from pathlib import Path
import random
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH, STACK_TOP
from cob import signed
from unicorn.x86_const import UC_X86_REG_ESI, UC_X86_REG_EDI

CONTROLLER = 0x100b000
PROJECTILE = 0x100a000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    # Stop after the three velocity stores and stack cleanup, before lifetime
    # setup. Original trig helpers and all launch arithmetic remain unmodified.
    native.mu.mem_write(0x49cecc, b'\xc3')
    native.mu.mem_write(0x49e11e, b'\xc3')
    rng = random.Random(1950)
    cases = []
    for index in range(1000):
        speed = [371370, 655359, 218453, 1000000][index % 4]
        heading = rng.randrange(65536)
        pitch = rng.randrange(65536)
        gravity = [8155, 0, 16000][index % 3]
        travel = [0, speed - 1, speed, speed + 1, 0xffffffff, rng.randrange(0x100000000)][index % 6]
        native.write(CONTROLLER + 0xc, DEFINITION)
        native.write(CONTROLLER + 0x10, travel)
        native.short(CONTROLLER + 0x16, heading)
        native.short(CONTROLLER + 0x18, pitch)
        native.write(DEFINITION + 0x68, speed)
        native.write(GAME + 0x14263, gravity)
        native.mu.reg_write(UC_X86_REG_ESI, CONTROLLER)
        native.mu.reg_write(UC_X86_REG_EDI, PROJECTILE)
        native.call(0x49ce4f, [])
        expected = [signed(native.read(PROJECTILE + offset)) for offset in [0x1c, 0x20, 0x24]]
        cases.append(dict(heading=heading, pitch=pitch, speed=speed, gravity=gravity, travel=travel, expected=expected))
    offsets = []
    for index in range(300):
        muzzle_z = rng.randrange(-2147483648, 2147483648)
        aim_z = rng.randrange(-2147483648, 2147483648)
        if index < 8:
            muzzle_z, aim_z = [0, 1, -1, 3, -3, 65536, -65536, 2147483647][index], 0
        native.write(STACK_TOP - 4 + 0x20, muzzle_z)
        native.write(STACK_TOP - 4 + 0x2c, aim_z)
        native.mu.reg_write(UC_X86_REG_ESI, CONTROLLER + 0x1b)
        native.call(0x49e0fb, [])
        offsets.append(dict(muzzle_z=muzzle_z, aim_z=aim_z, expected=signed(native.read(CONTROLLER + 0x10))))
    folder = Path('local/ballistics')
    folder.mkdir(exist_ok=True)
    (folder / 'native-launch.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases, offsets=offsets)), encoding='utf-8')
    print(f'NATIVE_BALLISTIC_LAUNCH {len(cases)} velocity cases, {len(offsets)} initialization offsets')


if __name__ == '__main__':
    main()
