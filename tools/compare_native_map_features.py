"""Compare map_feature_loader.py with native placement/removal over random grids and official multiplayer maps."""
import base64
import json
import struct
from pathlib import Path
from map_feature_loader import load


def expected(width, height, attributes, definitions, entries, extra):
    grid = load(width, height, [code for code in attributes], [dict(item, footprintx=item['footprintx'] & 0xffff, footprintz=item['footprintz'] & 0xffff) for item in definitions],
                [tuple(entry) for entry in entries], {key: dict(value, footprintx=value['footprintx'] & 0xffff, footprintz=value['footprintz'] & 0xffff) for key, value in extra.items()})
    codes = struct.pack(f'<{len(grid.codes)}H', *grid.codes)
    offsets = b''.join(bytes([row, column]) for row, column in zip(grid.rows, grid.columns))
    bits = bytes(int(flag) for flag in grid.instance)
    return codes, offsets, bits, [definition['name'] for definition in grid.definitions[len(definitions):]], len(grid.skipped_schema_features)


def main():
    data = json.loads(Path('local/features/native-map-features.json').read_text())
    checks = failures = 0
    cells = 0
    schema_cases = []
    for case in data['random'] + data['maps']:
        attributes = case['attributes']
        if isinstance(attributes, str):
            raw = base64.b64decode(attributes)
            attributes = list(struct.unpack(f'<{len(raw) // 2}H', raw))
        codes, offsets, bits, loaded, skipped = expected(case['width'], case['height'], attributes, case['definitions'], case.get('entries', []), case.get('extra', {}))
        native_codes = base64.b64decode(case['native']['codes'])
        native_offsets = bytearray(base64.b64decode(case['native']['offsets']))
        native_bits = base64.b64decode(case['native']['bits'])
        # Row/column bytes are only meaningful on continuation cells; anchors hold pool indices there.
        offsets = bytearray(offsets)
        for i in range(len(codes) // 2):
            if codes[i * 2:i * 2 + 2] != b'\xfe\xff':
                offsets[i * 2:i * 2 + 2] = b'\0\0'
            if native_codes[i * 2:i * 2 + 2] != b'\xfe\xff':
                native_offsets[i * 2:i * 2 + 2] = b'\0\0'
        offsets = bytes(offsets)
        cells += len(codes) // 2
        schema_cases.append(len([entry for entry in case.get('entries', []) if entry[0]]))
        for name, mine, theirs in [('codes', codes, native_codes), ('offsets', offsets, bytes(native_offsets)), ('bits', bits, native_bits),
                                   ('loaded', [n.lower() for n in loaded], [n.lower() for n in case['native']['loaded']]), ('null_cells', skipped, case['native']['null_cells'])]:
            checks += 1
            if mine != theirs:
                failures += 1
                if failures <= 8:
                    first = next((i for i in range(min(len(mine), len(theirs))) if mine[i] != theirs[i]), None) if isinstance(mine, bytes) else (mine, theirs)
                    print(f"MISMATCH {case.get('map', 'random')} {name}: {first}")
    summary = dict(random=len(data['random']), maps=len(data['maps']), cells=cells, schema_features=sum(schema_cases), checks=checks, failures=failures)
    Path('analysis/native-map-features-validation.json').write_text(json.dumps(dict(exe_sha256=data['exe_sha256'], **summary), indent=2) + '\n')
    print(f"MAP_FEATURES_NATIVE {checks - failures} / {checks} checks match ({summary['random']} random, {summary['maps']} maps, {cells} cells, {summary['schema_features']} schema features)")
    raise SystemExit(0 if failures == 0 else 1)


if __name__ == '__main__':
    main()
