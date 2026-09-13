"""Execute original normal-weapon reload arithmetic with supplied unit state."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, UNIT, DEFINITION
from native_cob_reference import EXE_HASH
from unicorn.x86_const import UC_X86_REG_EDI, UC_X86_REG_ESI, UC_X86_REG_EBX


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x49e4f2, b'\xc3')
    rng = random.Random(0x49e468)
    weapon, output = 0x100a000, 0x100b000
    cases = []
    for index in range(600):
        maximum = rng.randint(1, 32767)
        health = rng.randint(0, maximum)
        base, experience = rng.randint(0, 65535), rng.choice([0, 4, 5, 9, 10, 24, 25, 65535])
        if index < 8:
            maximum, health, base, experience = 100, [100, 0, 50, 100, 50, 0, 1, 99][index], 58, [0, 0, 0, 25, 25, 25, 4, 5][index]
        native.short(UNIT + 0x108, health)
        native.short(UNIT + 0xb8, experience)
        native.write(DEFINITION + 0x1fa, maximum)
        native.short(weapon + 0xe4, base)
        native.mu.reg_write(UC_X86_REG_EDI, UNIT)
        native.mu.reg_write(UC_X86_REG_ESI, output + 7)
        native.mu.reg_write(UC_X86_REG_EBX, weapon)
        native.call(0x49e468, [])
        cases.append(dict(base=base, health=health, maximum=maximum, experience=experience, expected=native.read(output) & 65535))
    folder = Path('local/weapon-reload')
    folder.mkdir(exist_ok=True)
    (folder / 'native.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_WEAPON_RELOAD {len(cases)} cases')


if __name__ == '__main__':
    main()
