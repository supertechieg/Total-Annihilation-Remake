"""Compare the original live ballistic integration branch with supplied world inputs.

Executes 0x49bb60 through the boundary at 0x49bd86. Collision handling,
expiration and launch/aim computation are outside this isolated oracle.
"""
import json
from pathlib import Path
import random

from native_movement_reference import MovementReference, GAME, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESI, UC_X86_REG_EBP, UC_X86_REG_EDI

PROJECTILE = 0x100a000


class BallisticReference(MovementReference):
    def __init__(self, executable, cob):
        super().__init__(executable, cob)
        # Return just before collision dispatch. The exercised branch has no
        # stack changes or intervening calls. No arithmetic is replaced.
        self.mu.mem_write(0x49bd86, b'\xc3')

    def integrate(self, case):
        self.mu.mem_write(PROJECTILE, bytes(0x6b))
        self.write(PROJECTILE, DEFINITION)
        self.write(DEFINITION + 0x111, 2)  # ballistic, no other weapon flags
        self.short(DEFINITION + 0xe6, case['flight_ticks'])
        self.write(PROJECTILE + 0x46, 100)
        self.write(GAME + 0x38a47, 1)  # supplied unexpired timer
        self.write(GAME + 0x14263, case['gravity'])
        for axis in range(3):
            self.write(PROJECTILE + 4 + axis * 4, case['position'][axis])
            self.write(PROJECTILE + 0x1c + axis * 4, case['velocity'][axis])
            self.write(GAME + 0x37ecc + axis * 4, case['drift'][axis])
        self.mu.reg_write(UC_X86_REG_EAX, 2)
        self.mu.reg_write(UC_X86_REG_ESI, DEFINITION)
        self.mu.reg_write(UC_X86_REG_EBP, PROJECTILE)
        self.mu.reg_write(UC_X86_REG_EDI, 0)
        self.call(0x49bb60, [])
        return dict(position=[signed(self.read(PROJECTILE + 4 + axis * 4)) for axis in range(3)],
                    velocity=[signed(self.read(PROJECTILE + 0x1c + axis * 4)) for axis in range(3)])


def main():
    native = BallisticReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    rng = random.Random(1948)
    cases = []
    for index in range(1000):
        case = dict(position=[rng.randrange(-2147483648, 2147483648) for _ in range(3)],
                    velocity=[rng.randrange(-2147483648, 2147483648) for _ in range(3)],
                    drift=[rng.randrange(-65536, 65537) for _ in range(3)],
                    gravity=[0, 8155, 16384, -100, 2147483647][index % 5],
                    flight_ticks=0 if index % 2 else 30)
        case['expected'] = native.integrate(case)
        cases.append(case)
    position, velocity = [0, 12 * 65536, 0], [371370, 196608, 0]
    for tick in range(120):
        case = dict(position=position, velocity=velocity, drift=[0, 0, 0], gravity=8155, flight_ticks=0)
        case['expected'] = native.integrate(case)
        position, velocity = case['expected']['position'], case['expected']['velocity']
        cases.append(case)
    folder = Path('local/ballistics')
    folder.mkdir(exist_ok=True)
    (folder / 'native-integration.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_BALLISTIC_REFERENCE {len(cases)} integration cases')


if __name__ == '__main__':
    main()
