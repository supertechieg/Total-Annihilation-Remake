"""Compare native model height and footprint bounds for all prepared units."""
import json
from pathlib import Path
import struct
from native_movement_reference import MovementReference, DEFINITION
from native_cob_reference import EXE_HASH
from prepare_units import Content
from cob import signed
from unicorn.x86_const import UC_X86_REG_EBP

MODEL = 0x1500000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(MODEL, 0x100000)
    native.mu.mem_write(0x42d125, b'\xc3')
    content = Content(Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    index = json.loads(Path('local/unit-assets/index.json').read_text())
    cases = []
    for unit_id, entry in index['units'].items():
        unit = json.loads((Path('local/unit-assets') / entry['path']).read_text())
        raw = content.read(unit['model']['source'])
        native.mu.mem_write(MODEL, raw)

        def relocate(offset):
            for field in (0x24, 0x2c, 0x30):
                value = struct.unpack_from('<I', raw, offset + field)[0]
                native.write(MODEL + offset + field, MODEL + value if value else 0)
                if value and field != 0x24:
                    relocate(value)

        relocate(0)
        # Original axis conversion preserves Y, then original recursive height.
        native.call(0x4cb590, [MODEL])
        height = signed(native.call(0x4cb5f0, [MODEL]))
        fields = unit['definition']
        x, z = int(fields['footprintx']), int(fields['footprintz'])
        native.short(DEFINITION + 0x14a, x)
        native.short(DEFINITION + 0x14c, z)
        native.write(DEFINITION + 0x162, 0)
        native.write(DEFINITION + 0x16e, height)
        native.mu.reg_write(UC_X86_REG_EBP, DEFINITION)
        native.call(0x42d080, [], this=x)
        cases.append(dict(unit=unit_id, height=height,
                          lower=[signed(native.read(DEFINITION + 0x15e + axis * 4)) for axis in range(3)],
                          upper=[signed(native.read(DEFINITION + 0x16a + axis * 4)) for axis in range(3)]))
    folder = Path('local/splash')
    folder.mkdir(exist_ok=True)
    (folder / 'native-unit-bounds.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_UNIT_BOUNDS {len(cases)} units')


if __name__ == '__main__':
    main()
