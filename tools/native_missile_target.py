"""Original non-cruise missile target pointer selection, with changing targets."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    projectile, other, unit = 0x100a000, 0x100b000, 0x100c000
    rng = random.Random(0x49b3e0)
    cases = []
    native.write(projectile, DEFINITION)
    native.write(DEFINITION + 0x111, 0)
    for index in range(48):
        saved = [rng.randrange(-100000000, 100000000) for _ in range(3)]
        moving = [rng.randrange(-100000000, 100000000) for _ in range(3)]
        intercept = [rng.randrange(-100000000, 100000000) for _ in range(3)]
        has_projectile = index % 6 in (0, 1)
        has_unit = index % 6 in (0, 2, 3)
        valid = index % 6 in (0, 2)
        native.write(projectile + 0x56, other if has_projectile else 0)
        native.write(projectile + 0x4e, unit if has_unit else 0)
        native.write(unit + 0x110, 0x10000000 if valid else 0)
        for axis in range(3):
            native.write(projectile + 0x28 + axis * 4, saved[axis])
            native.write(other + 4 + axis * 4, intercept[axis])
            native.write(unit + 0x6a + axis * 4, moving[axis])
        address = native.call(0x49b3e0, [projectile])
        source = {other + 4: 'projectile', unit + 0x6a: 'unit', projectile + 0x28: 'saved'}[address]
        cases.append(dict(saved=saved, unit=moving if has_unit else None, unit_valid=valid,
                          projectile=intercept if has_projectile else None,
                          expected=dict(source=source, point=[signed(native.read(address + axis * 4)) for axis in range(3)])))
    Path('local/ballistics/missile-target.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_MISSILE_TARGET {len(cases)} cases')


if __name__ == '__main__':
    main()
