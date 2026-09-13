"""Execute original direct-launch deadline block with supplied weapon fields."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH
from unicorn.x86_const import UC_X86_REG_EAX


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x49cb61, b'\xc3')
    rng = random.Random(0x49cb1c)
    cases = []
    for index in range(240):
        tick = rng.randrange(0x100000000)
        speed = [0, 546133, 1179647, 1419946][index % 4]
        distance = [0, 400, 600, 604, 65536, 70000][(index // 4) % 6]
        timer = [0, 60, 150, 65535][(index // 6) % 4]
        no_auto = bool((index // 3) % 2)
        native.write(GAME + 0x38a47, tick)
        native.write(DEFINITION + 0x68, speed)
        native.write(DEFINITION + 0xdc, distance)
        native.short(DEFINITION + 0xe6, timer)
        native.write(DEFINITION + 0x111, 0x8000000 if no_auto else 0)
        native.mu.reg_write(UC_X86_REG_EAX, DEFINITION)
        result = native.call(0x49cb1c, [])
        cases.append(dict(tick=tick, speed=speed, range=distance, timer=timer, no_auto=no_auto, expected=result))
    Path('local/ballistics/direct-deadline.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_DIRECT_DEADLINE {len(cases)} cases')


if __name__ == '__main__':
    main()
