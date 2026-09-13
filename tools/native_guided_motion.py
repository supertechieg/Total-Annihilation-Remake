"""Original guided self-propelled update; collision and consolidation isolated."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed

POOL = 0x1500000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(POOL, 0x10000)
    native.mu.mem_write(0x49b090, b'\xc2\x08\x00')
    native.mu.mem_write(0x49ae20, b'\xc3')
    rng = random.Random(0x49ba53)
    cases = []
    for index in range(240):
        native.mu.mem_write(POOL, bytes(0x6b))
        maximum = [546133, 1419946, 1179647][index % 3]
        speed = [0, maximum // 2, maximum - 1, maximum, maximum + 1][index % 5]
        acceleration = [0, 1000, 100000][(index // 3) % 3]
        tick = rng.randrange(0x100000000)
        deadline = [tick, (tick + 1) & 0xffffffff, (tick - 1) & 0xffffffff][index % 3]
        position = [100 * 65536, 100 * 65536, 100 * 65536]
        velocity = [rng.randrange(-1000000, 1000000) for _ in range(3)]
        heading, pitch = rng.randrange(65536), rng.randrange(65536)
        gravity = [0, 4369, 8155][(index // 9) % 3]
        native.write(GAME + 0x141f7, POOL)
        native.write(GAME + 0x141f3, 1)
        native.write(GAME + 0x38a47, tick)
        native.write(GAME + 0x14263, gravity)
        native.write(GAME + 0x142f7, 0)
        native.write(DEFINITION + 0x111, 0x101001)
        native.write(DEFINITION + 0x68, maximum)
        native.write(DEFINITION + 0x70, acceleration)
        target = [rng.randrange(50, 150) * 65536 for _ in range(3)]
        turn = [0, 999, 1099, 65535][index % 4]
        native.short(DEFINITION + 0xe8, turn)
        for axis in range(3):
            native.write(POOL + 0x28 + axis * 4, target[axis])
        native.write(POOL, DEFINITION)
        native.write(POOL + 0x46, deadline)
        native.write(POOL + 0x3a, speed)
        native.short(POOL + 0x36, heading)
        native.short(POOL + 0x38, pitch)
        for axis in range(3):
            native.write(POOL + 4 + axis * 4, position[axis])
            native.write(POOL + 0x1c + axis * 4, velocity[axis])
        native.call(0x49b720, [])
        cases.append(dict(tick=tick, deadline=deadline, maximum=maximum, speed=speed, acceleration=acceleration,
                          position=position, velocity=velocity, heading=heading, pitch=pitch, gravity=gravity, target=target, turn=turn,
                          expected=dict(heading=native.read(POOL + 0x36) & 65535, pitch=native.read(POOL + 0x38) & 65535, position=[signed(native.read(POOL + 4 + axis * 4)) for axis in range(3)],
                                        velocity=[signed(native.read(POOL + 0x1c + axis * 4)) for axis in range(3)], speed=native.read(POOL + 0x3a))))
    Path('local/ballistics/guided-motion.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_GUIDED_MOTION {len(cases)} cases')


if __name__ == '__main__':
    main()
