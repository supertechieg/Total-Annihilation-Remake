"""Execute the original movement-definition initializer for omitted FBI limits."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    output = 0x1020000
    native.call(0x4402e0, [], this=output)
    actual = struct.unpack('<hhB', native.mu.mem_read(output + 8, 5))
    expected = (10000, -10000, 255)
    differences = [] if actual == expected else [dict(actual=actual, expected=expected)]
    Path('analysis/native-placement-defaults-validation.json').write_text(json.dumps(dict(
        exe_sha256=EXE_HASH, cases=3, differences=differences,
        maxwaterdepth=actual[0], minwaterdepth=actual[1], maxslope=actual[2],
        scope='Original 0x4402e0 initializer only; excludes movement-class resolution and placement geometry'
    ), indent=2) + '\n', encoding='utf-8')
    print('PLACEMENT_DEFAULTS', '3 / 3 match' if not differences else 'FAIL')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
