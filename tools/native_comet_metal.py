"""Run the original feature pass on all imported Comet Catcher cells."""
import hashlib
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH, STACK_TOP, STOP
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP


def main():
    metadata = json.loads(Path('local/viewer-assets/metal.json').read_text())
    expected = Path('local/viewer-assets/metal.bin').read_bytes()
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    cells, definitions = 0x1600000, 0x1030000
    count = metadata['width'] * metadata['height']
    native.mu.mem_map(cells, (count * 13 + 4095) & ~4095)
    data = bytearray(count * 13)
    for i in range(count):
        data[i * 13 + 7] = metadata['surface']
        struct.pack_into('<H', data, i * 13 + 8, 65535)
    for index, feature in enumerate(metadata['placements']):
        definition = definitions + index * 256
        native.mu.mem_write(definition, bytes(256))
        native.short(definition + 0x94, feature['width'])
        native.short(definition + 0x96, feature['height'])
        native.mu.mem_write(definition + 0xf0, struct.pack('<f', feature['metal'] & 65535))
        native.mu.mem_write(definition + 0xff, bytes([2 if feature['indestructible'] else 0]))
        struct.pack_into('<H', data, (feature['z'] * metadata['width'] + feature['x']) * 13 + 8, index)
    native.mu.mem_write(cells, bytes(data))
    for offset, value in [(0x14233, metadata['width']), (0x14237, metadata['height']), (0x14287, cells), (0x1426f, definitions)]:
        native.write(GAME + offset, value)
    native.write(STACK_TOP - 4, STOP)
    native.mu.reg_write(UC_X86_REG_ESP, STACK_TOP - 4)
    native.mu.emu_start(0x422040, STOP, timeout=10000000, count=10000000)
    if native.mu.reg_read(UC_X86_REG_EIP) != STOP:
        raise RuntimeError('Original map pass did not finish')
    actual = bytes(native.mu.mem_read(cells, count * 13))[7::13]
    differences = sum(a != b for a, b in zip(actual, expected))
    report = dict(cells=count, mismatches=differences, exe_sha256=EXE_HASH, metal_sha256=hashlib.sha256(actual).hexdigest(),
                  scope='Full original feature pass over imported Comet Catcher placements; TNT decoding and definition loading reconstructed outside native routine')
    Path('analysis/native-comet-metal-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'COMET_METAL {count - differences} / {count} cells match')
    if len(actual) != len(expected) or differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
