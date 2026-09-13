"""Original line-of-sight projectile movement and expiration, collision stubbed."""
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
    rng = random.Random(0x49bc8b)
    cases = []
    for index in range(240):
        native.mu.mem_write(POOL, bytes(0x6b))
        tick = rng.randrange(0x100000000)
        deadline = [tick, (tick + 1) & 0xffffffff, (tick - 1) & 0xffffffff, 0, 0xffffffff][index % 5]
        position = [rng.randrange(-2147483648, 2147483648) for _ in range(3)]
        velocity = [rng.randrange(-1000000, 1000000) for _ in range(3)]
        native.write(GAME + 0x141f7, POOL)
        native.write(GAME + 0x141f3, 1)
        native.write(GAME + 0x142f7, 0)
        native.write(GAME + 0x38a47, tick)
        native.write(DEFINITION + 0x111, 1)
        native.write(POOL, DEFINITION)
        native.write(POOL + 0x46, deadline)
        for axis in range(3):
            native.write(POOL + 4 + axis * 4, position[axis])
            native.write(POOL + 0x1c + axis * 4, velocity[axis])
        native.call(0x49b720, [])
        expected = [signed(native.read(POOL + 4 + axis * 4)) for axis in range(3)]
        removed = bool(native.read(POOL + 0x69) & 2)
        if removed != (tick >= deadline) or expected != (position if removed else [signed((a + b) & 0xffffffff) for a, b in zip(position, velocity)]):
            raise AssertionError(f'Unexpected native line-of-sight transition at case {index}: {position=} {velocity=} {expected=} {removed=} {tick=} {deadline=}')
        cases.append(dict(tick=tick, deadline=deadline, position=position, velocity=velocity, expected=expected, removed=removed))
    folder = Path('local/ballistics')
    (folder / 'emg-lifetime.json').write_text(json.dumps(cases))
    Path('analysis/native-emg-lifetime-validation.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=len(cases), mismatches=0,
        scope='Complete 0x49b720 with line-of-sight flag only; collision and pool consolidation stubbed; unsigned expiration precedes signed-wrapped movement'), indent=2) + '\n')
    print(f'NATIVE_EMG_LIFETIME {len(cases)} cases pass')


if __name__ == '__main__':
    main()
