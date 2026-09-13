"""Original weapon damage selection/scaling, stopping at health dispatch."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME, UNIT, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed

PROJECTILE, ATTACKER, TARGET_DEF = 0x100a000, 0x100b000, 0x1007000
OVERRIDES, ENTRIES, NAME = 0x100c000, 0x100d000, 0x100e000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    # Preserve the complete damage routine, including name lookup and atan2.
    # Replace only health/kill dispatch; this oracle does not mutate a world.
    native.mu.mem_write(0x489bb0, b'\xc2\x14\x00')
    native.write(PROJECTILE, DEFINITION)
    native.write(UNIT + 0x92, TARGET_DEF)
    native.mu.mem_write(TARGET_DEF + 0x20, b'CORRAID\0')
    native.write(OVERRIDES + 5, ENTRIES)
    native.write(OVERRIDES + 9, ENTRIES + 8)
    native.write(ENTRIES, NAME)
    rng = random.Random(1954)
    cases = []
    for index in range(600):
        base = rng.randrange(65536)
        override = rng.randrange(10000)
        override_mode = index % 3  # absent, matching, nonmatching
        multiplier = [0.0, 0.1, 0.5, 1.0, 1.5][index % 5]
        bits = struct.unpack('<I', struct.pack('<f', multiplier))[0]
        multiplier = struct.unpack('<f', struct.pack('<I', bits))[0]
        experience = rng.randrange(40)
        flags = [0, 0x80, 0x100, 0x180][index % 4]
        has_source = index % 7 != 0
        native.short(DEFINITION + 0xd4, base)
        native.write(DEFINITION + 0x64, OVERRIDES if override_mode else 0)
        native.mu.mem_write(NAME, b'corraid\0' if override_mode == 1 else b'armflash\0')
        native.write(ENTRIES + 4, override)
        native.write(PROJECTILE + 0x52, ATTACKER if has_source else 0)
        native.short(ATTACKER + 0xb8, experience)
        native.short(GAME + 0x37f2f, flags)
        expected = signed(native.call(0x499cd0, [PROJECTILE, UNIT, bits]))
        cases.append(dict(base=base, override=override, override_mode=override_mode, multiplier=multiplier,
                          experience=experience, flags=flags, has_source=has_source, expected=expected))
    folder = Path('local/splash')
    folder.mkdir(exist_ok=True)
    (folder / 'native-damage.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_DAMAGE_REFERENCE {len(cases)} cases')


if __name__ == '__main__':
    main()
