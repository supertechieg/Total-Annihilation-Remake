"""Original GET_VALUE 4 (HEALTH) engine callback executed in Unicorn.

Runs the value-get function 0x480770 (engine vtable 0x4fd698 slot 17) with key 4 against synthetic unit and
definition records (health word at unit+0x108, definition pointer at unit+0x92, dword maxdamage at def+0x1fa) and
writes local/scripts/native-health-read.json for godot/compare_native_health_read.gd (VM.health_read).
"""
import json
import random
from pathlib import Path
from native_cob_reference import NativeReference, EXE_HASH

OBJECT = 0x1380000
HOLDER = 0x1381000
UNIT = 0x1382000
DEFINITION = 0x1383000


def main():
    native = NativeReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.write(OBJECT + 0x540, HOLDER)
    native.write(HOLDER + 0xc, UNIT)
    native.write(UNIT + 0x92, DEFINITION)
    rng = random.Random(0x4807ca)
    healths = sorted(set(list(range(-32768, 32768, 409)) + [-32768, -1, 0, 1, 49, 50, 99, 100, 101, 659, 660, 1999, 2000, 2001,
                                                            2999, 3000, 3001, 32766, 32767, 32768, 65535, 65536, 70000]))
    maxdamages = [1, 3, 7, 66, 100, 330, 1000, 2000, 3000, 4999, 32767, 65535, 0x7fffffff, 0x80000000, 0xffffffff]
    cases = []
    for maxdamage in maxdamages:
        for health in healths + [rng.randrange(-40000, 70000) for _ in range(16)]:
            native.mu.mem_write(UNIT + 0x108, (health & 0xffff).to_bytes(2, 'little'))
            native.write(DEFINITION + 0x1fa, maxdamage)
            value = native.call(0x480770, [4, 0, 0, 0, 0], this=OBJECT)
            cases.append([health, maxdamage, value])
    output = Path('local/scripts/native-health-read.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dict(exe_sha256=EXE_HASH, function='0x480770 key 4', cases=cases)), encoding='utf-8')
    print(f'NATIVE_HEALTH_READ {len(cases)} cases -> {output}')


if __name__ == '__main__':
    main()
