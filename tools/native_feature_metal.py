"""Compare original full feature-metal pass against reconstructed overlay."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH
from terrain_metal import feature_metal


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    cells, definitions = 0x1020000, 0x1030000
    native.write(GAME + 0x14233, 8)
    native.write(GAME + 0x14237, 8)
    native.write(GAME + 0x14287, cells)
    native.write(GAME + 0x1426f, definitions)
    differences = []
    count = 0
    for metal in [0, 1, 127, 255, 256, 65535]:
        for indestructible in [False, True]:
            for x, z, width, height in [(0, 0, 2, 2), (6, 6, 4, 3), (2, 2, 3, 4), (1, 1, 0, 2)]:
                placements = [dict(x=x, z=z, width=width, height=height, metal=metal, indestructible=indestructible),
                              dict(x=3, z=3, width=2, height=2, metal=42, indestructible=True)]
                base = bytes((i * 3) & 255 for i in range(64))
                for i in range(64):
                    native.mu.mem_write(cells + i * 13 + 7, bytes([base[i]]))
                    native.short(cells + i * 13 + 8, 65535)
                for index, feature in enumerate(placements):
                    definition = definitions + index * 256
                    native.mu.mem_write(definition, bytes(256))
                    native.short(definition + 0x94, feature['width'])
                    native.short(definition + 0x96, feature['height'])
                    native.mu.mem_write(definition + 0xf0, struct.pack('<f', feature['metal']))
                    native.mu.mem_write(definition + 0xff, bytes([2 if feature['indestructible'] else 0]))
                    native.short(cells + (feature['z'] * 8 + feature['x']) * 13 + 8, index)
                native.call(0x422040, [])
                actual = bytes(native.mu.mem_read(cells + i * 13 + 7, 1)[0] for i in range(64))
                expected = feature_metal(8, 8, base, placements)
                count += 1
                if actual != expected:
                    differences.append(dict(placements=placements, native=list(actual), reconstructed=list(expected)))
    report = dict(cases=count, differences=differences, exe_sha256=EXE_HASH,
                  scope='Full original feature-metal pass and map lookup; supplied loaded features/base bytes; excludes TNT decoding and feature placement validation')
    Path('analysis/native-feature-metal-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'FEATURE_METAL {count - len(differences)} / {count} match')
    if differences:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
