"""Original blast-to-unit box distance and falloff, before damage dispatch."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, UNIT, DEFINITION
from native_cob_reference import EXE_HASH, STACK_TOP
from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_ESI, UC_X86_REG_EBX

FRAME, POINT, PROJECTILE, UNIT_DEF = 0x100b000, 0x1009000, 0x100a000, 0x1007000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x49a3ee, b'\xc3')
    native.mu.mem_write(0x49a411, b'\xc3')
    native.write(FRAME + 0xc, POINT)
    native.write(UNIT + 0x92, UNIT_DEF)
    native.write(PROJECTILE, DEFINITION)
    rng = random.Random(1953)
    cases = []
    for index in range(600):
        center = [rng.randrange(100, 500) * 65536 for _ in range(3)]
        point = [coordinate + rng.randrange(-40 * 65536, 40 * 65536) for coordinate in center]
        lower = [-rng.randrange(1, 20) * 65536 for _ in range(3)]
        upper = [rng.randrange(1, 20) * 65536 for _ in range(3)]
        radius = [8, 16, 32, 64][index % 4]
        edge = [0.0, 0.1, 0.5, 1.0][index % 4]
        if index < 6:
            center, lower, upper = [0, 0, 0], [0, 0, 0], [0, 0, 0]
            radius, edge = 16, 0.0
            point = [[0, 0, 0], [8 * 65536, 0, 0], [15 * 65536, 0, 0], [16 * 65536, 0, 0], [65535, 0, 0], [65536, 0, 0]][index]
        for axis in range(3):
            native.write(POINT + axis * 4, point[axis])
            native.write(UNIT + 0x6a + axis * 4, center[axis])
            native.write(UNIT_DEF + 0x15e + axis * 4, lower[axis])
            native.write(UNIT_DEF + 0x16a + axis * 4, upper[axis])
        native.mu.mem_write(DEFINITION + 0xd8, struct.pack('<f', edge))
        edge = struct.unpack('<f', struct.pack('<f', edge))[0]
        native.write(STACK_TOP - 4 + 0x4c, radius)
        native.write(STACK_TOP - 4 + 0x74, 0)
        native.mu.reg_write(UC_X86_REG_EBP, FRAME)
        native.mu.reg_write(UC_X86_REG_ESI, UNIT)
        native.mu.reg_write(UC_X86_REG_EBX, PROJECTILE)
        native.call(0x49a2aa, [])
        expected = struct.unpack('<f', native.mu.mem_read(STACK_TOP - 4 + 0x74, 4))[0]
        cases.append(dict(point=point, center=center, lower=lower, upper=upper, radius=radius, edge=edge, expected=expected))
    folder = Path('local/splash')
    folder.mkdir(exist_ok=True)
    (folder / 'native-falloff.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_SPLASH_REFERENCE {len(cases)} cases')


if __name__ == '__main__':
    main()
