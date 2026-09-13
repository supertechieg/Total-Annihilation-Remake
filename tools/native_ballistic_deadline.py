"""Original cannon deadline arithmetic, including burnblow horizontal travel."""
import json
from pathlib import Path
import random
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH, STACK_TOP
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBP


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x49cf40, b'\xc3')  # EAX is the completed deadline.
    rng = random.Random(1959)
    cases = []
    for index in range(600):
        start = [rng.randrange(-50000000, 50000000) for _ in range(3)]
        target = [rng.randrange(-50000000, 50000000) for _ in range(3)]
        speed = rng.randrange(1, 1000000)
        tick, timer = rng.randrange(0x100000000), rng.randrange(65536)
        burnblow = bool(index % 2)
        for axis in range(3):
            native.write(0x100a000 + axis * 4, start[axis])
            native.write(0x100b000 + axis * 4, target[axis])
        native.write(STACK_TOP - 4 + 0x1c, 0x100a000)
        native.write(STACK_TOP - 4 + 0x20, 0x100b000)
        native.write(DEFINITION + 0x111, 0x800000 if burnblow else 0)
        native.short(DEFINITION + 0xe6, timer)
        native.write(GAME + 0x38a47, tick)
        native.mu.reg_write(UC_X86_REG_EAX, DEFINITION)
        native.mu.reg_write(UC_X86_REG_EBP, speed)
        expected = native.call(0x49cecc, [])
        cases.append(dict(start=start, target=target, speed=speed, tick=tick, timer=timer, burnblow=burnblow, expected=expected))
    folder = Path('local/ballistics')
    (folder / 'native-deadline.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_BALLISTIC_DEADLINE {len(cases)} cases')


if __name__ == '__main__':
    main()
