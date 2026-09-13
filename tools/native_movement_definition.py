"""Compare original movement field loader with supplied integer TDF lookups."""
import json
import random
import struct
from pathlib import Path
from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH
from movement_definition import movement_definition
from unicorn import UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EAX


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x4c46c0, b'\xc2\x08\x00')
    fields = {}

    def lookup(mu, address, size, user):
        if address != 0x4c46c0:
            return
        sp = mu.reg_read(UC_X86_REG_ESP)
        pointer = native.read(sp + 4)
        key = bytes(mu.mem_read(pointer, 32)).split(b'\0')[0].decode('ascii').lower()
        mu.reg_write(UC_X86_REG_EAX, int(fields.get(key, native.read(sp + 8))) & 0xffffffff)

    native.mu.hook_add(UC_HOOK_CODE, lookup, begin=0x4c46c0, end=0x4c46c0)
    rng = random.Random(440340)
    names = list(movement_definition({}))
    cases = [{}]
    for _ in range(200):
        cases.append({key: rng.choice([-65537, -32769, -1, 0, 2, 12, 255, 256, 32768, 65537])
                      for key in names if rng.randrange(2)})
    differences = []
    for fields in cases:
        native.call(0x4402e0, [], this=0x1020000)
        native.call(0x440340, [0x1030000], this=0x1020000)
        values = struct.unpack('<hhhhBBBB', native.mu.mem_read(0x1020004, 12))
        expected = dict(zip(names, values))
        actual = movement_definition(fields)
        if expected != actual:
            differences.append(dict(fields=fields, expected=expected, actual=actual))
    Path('analysis/native-movement-definition-validation.json').write_text(json.dumps(dict(
        cases=len(cases), differences=differences, exe_sha256=EXE_HASH,
        scope='Original 0x4402e0 and 0x440340; integer TDF lookup stubbed, excludes class lookup and pathfinding'
    ), indent=2) + '\n', encoding='utf-8')
    print(f'MOVEMENT_DEFINITION {len(cases) - len(differences)} / {len(cases)} match')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
