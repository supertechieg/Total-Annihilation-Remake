"""Original missile steering toward supplied points; excludes target acquisition."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, DEFINITION
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    projectile, target = 0x100a000, 0x100b000
    rng = random.Random(0x49b520)
    cases = []
    for index in range(624):
        position = [rng.randrange(-1000, 1000) * 65536 for _ in range(3)]
        destination = [rng.randrange(-1000, 1000) * 65536 for _ in range(3)]
        if index < 8:
            position = [0, 0, 0]
            destination = [[0, 0, 0], [0, 0, 65536], [65536, 0, 0], [0, 65536, 0]][index % 4]
        heading, pitch = rng.randrange(65536), rng.randrange(65536)
        if index < 8:
            heading, pitch = 0, 0
        turn = [0, 1, 1000, 30000, 33000, 65535][index % 6]
        flags = 0x800000 if index % 2 else 0
        if index >= 600:
            position, destination = [0, 0, 0], [0, 0, -65536]
            delta = [0, 999, 1000, 1001, 27000, 27001, 32767, 32768, -999, -1000, -27001, -32767][(index - 600) % 12]
            heading, pitch = (-delta) & 65535, 0
            turn, flags = 1000, 0x800000 if index >= 612 else 0
        native.write(projectile, DEFINITION)
        native.write(DEFINITION + 0x111, flags)
        native.short(DEFINITION + 0xe8, turn)
        native.short(projectile + 0x36, heading)
        native.short(projectile + 0x38, pitch)
        for axis in range(3):
            native.write(projectile + 4 + axis * 4, position[axis])
            native.write(target + axis * 4, destination[axis])
        result = native.call(0x49b520, [projectile, target])
        cases.append(dict(position=position, target=destination, heading=heading, pitch=pitch, turn=turn, flags=flags,
                          expected=dict(heading=native.read(projectile + 0x36) & 65535, pitch=native.read(projectile + 0x38) & 65535, accepted=result)))
    Path('local/ballistics/missile-steering.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_MISSILE_STEERING {len(cases)} cases')


if __name__ == '__main__':
    main()
