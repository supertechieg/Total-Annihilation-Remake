"""Original line-of-sight beam update: head movement, delayed tail release and expiration; collision stubbed."""
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
    rng = random.Random(0x49bc0c)
    cases = []
    for index in range(600):
        native.mu.mem_write(POOL, bytes(0x6b))
        tick = rng.randrange(0x100000000)
        duration = [0, 1, 2, 6, 30, 0xffff][index % 6]
        # Launch ticks straddle the strict launch + duration < tick release test, including 32-bit wrap.
        launch = [tick - duration, tick - duration - 1, tick - duration + 1, tick, tick - 100, rng.randrange(0x100000000)][(index // 6) % 6] & 0xffffffff
        deadline = [tick + 1, tick + 50, tick, tick - 1, 0xffffffff][(index // 36) % 5] & 0xffffffff
        released = index % 7 == 3
        beam = index % 11 != 5
        head = [rng.randrange(-2147483648, 2147483648) for _ in range(3)]
        tail = [rng.randrange(-2147483648, 2147483648) for _ in range(3)]
        velocity = [rng.randrange(-1000000, 1000000) for _ in range(3)]
        native.write(GAME + 0x141f7, POOL)
        native.write(GAME + 0x141f3, 1)
        native.write(GAME + 0x142f7, 0)
        native.write(GAME + 0x38a47, tick)
        native.write(DEFINITION + 0x111, 1 | (8 if beam else 0))
        native.short(DEFINITION + 0xf0, duration)
        native.write(POOL, DEFINITION)
        native.write(POOL + 0x42, launch)
        native.write(POOL + 0x46, deadline)
        native.short(POOL + 0x69, 1 if released else 0)
        for axis in range(3):
            native.write(POOL + 4 + axis * 4, head[axis])
            native.write(POOL + 0x10 + axis * 4, tail[axis])
            native.write(POOL + 0x1c + axis * 4, velocity[axis])
        native.call(0x49b720, [])
        flags = native.read(POOL + 0x69) & 0xffff
        cases.append(dict(tick=tick, launch=launch, deadline=deadline, duration=duration, beam=beam, released=released,
                          head=head, tail=tail, velocity=velocity,
                          expected=dict(head=[signed(native.read(POOL + 4 + axis * 4)) for axis in range(3)],
                                        tail=[signed(native.read(POOL + 0x10 + axis * 4)) for axis in range(3)],
                                        released=bool(flags & 1), removed=bool(flags & 2))))
    folder = Path('local/ballistics')
    folder.mkdir(exist_ok=True)
    (folder / 'beam-motion.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_BEAM_MOTION {len(cases)} cases')


if __name__ == '__main__':
    main()
