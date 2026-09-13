"""Execute original map-loader gravity selection and conversion block."""
import json
from pathlib import Path
from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH, STACK_TOP
from cob import signed
from unicorn.x86_const import UC_X86_REG_ESI, UC_X86_REG_EBP
from map_environment import gravity_raw


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_write(0x483842, b'\xc3')
    descriptor, output = 0x100b000, 0x100a000
    cases = []
    for version in [0x1020, 0x2000]:
        for header in [0, 1, 60, 112, 255, 1000]:
            for override in [-1, 0, 1, 60, 112, 255, 1000, 2147483647]:
                native.write(descriptor + 0xd3c, override)
                native.write(STACK_TOP - 4 + 0x18, version)
                native.write(STACK_TOP - 4 + 0x30, header)
                native.mu.reg_write(UC_X86_REG_ESI, 0)
                native.mu.reg_write(UC_X86_REG_EBP, output)
                native.call(0x4837e9, [], this=descriptor)
                expected = signed(native.read(output + 0x68))
                actual = gravity_raw(version, header, override)
                cases.append(dict(version=version, header=header, override=override, expected=expected, actual=actual))
    mismatches = [case for case in cases if case['expected'] != case['actual']]
    folder = Path('local/ballistics')
    folder.mkdir(exist_ok=True)
    (folder / 'native-gravity.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    report = dict(exe_sha256=EXE_HASH, cases=len(cases), mismatches=len(mismatches),
                  scope='Map-loader gravity source selection, default, original x87 scale and signed32 storage; supplied descriptor/header fields')
    (folder / 'native-gravity-comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'NATIVE_MAP_GRAVITY {len(cases) - len(mismatches)} / {len(cases)} cases match')
    if mismatches:
        print(mismatches[:3])
        raise SystemExit(1)


if __name__ == '__main__':
    main()
