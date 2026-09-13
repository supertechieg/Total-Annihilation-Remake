"""Original map-loader tidal selection with supplied descriptor values."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH
from unicorn.x86_const import UC_X86_REG_EBP
from map_environment import tidal_strength


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    descriptor, output = 0x1010000, 0x1020000
    native.write(GAME + 0x391e9, descriptor)
    native.mu.mem_write(0x483873, b'\xc3')
    differences = []
    values = [-100, -1, -0.00001, -0.0, 0, 0.1, 0.5, 1, 20, 1000]
    for value in values:
        native.mu.mem_write(descriptor + 0xd40, struct.pack('<f', value))
        native.mu.reg_write(UC_X86_REG_EBP, output)
        native.call(0x483842, [])
        expected = struct.unpack('<f', native.mu.mem_read(output + 0x6c, 4))[0]
        actual = tidal_strength(value)
        if actual != expected:
            differences.append(dict(value=value, expected=expected, actual=actual))
    Path('analysis/native-map-tidal-validation.json').write_text(json.dumps(dict(cases=len(values), differences=differences, exe_sha256=EXE_HASH,
        scope='Original map-loader tidal selection with supplied finite descriptor values; excludes text parsing'), indent=2) + '\n')
    print(f'MAP_TIDAL {len(values) - len(differences)} / {len(values)} match')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
