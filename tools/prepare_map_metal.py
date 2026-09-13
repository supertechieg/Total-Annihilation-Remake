"""Prepare Comet Catcher's metal and static feature-blocking grids from original TNT/OTA and feature definitions."""
import hashlib
import json
from pathlib import Path
from collections import Counter
from prepare_units import Content
from ta_assets import Archive, FormatError, span, unpack
from tdf import parse
from terrain_metal import feature_metal
from feature_blocking import blocking_flag, feature_blocking


def main():
    root = Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation')
    output = Path('local/viewer-assets')
    archive = Archive(root / 'ccmaps.ccx')
    data = archive.extract('maps/comet catcher.tnt')
    ota = archive.extract('maps/comet catcher.ota')
    header = unpack('<16I', data)
    version, width, height, _, attrs_at = header[:5]
    if version != 0x2000:
        raise FormatError('Metal import currently supports TNT 0x2000')
    names = [span(data, header[8] + i * 132 + 4, 128).split(b'\0')[0].decode('latin-1').lower() for i in range(header[7])]
    content = Content(root)
    definitions = {}
    for path in sorted(content.paths):
        if not path.startswith('features/') or not path.endswith('.tdf'):
            continue
        for name, fields in parse(content.read(path)).items():
            name = name.lower()
            if name in names:
                if name in definitions:
                    raise FormatError('Ambiguous feature definition: ' + name)
                definitions[name] = dict(fields=fields, path=path)
    missing = set(names) - definitions.keys()
    if missing:
        raise FormatError(f'Missing feature definitions: {missing}')
    surface = max(0, int(parse(ota)['globalheader'].get('surfacemetal', '-1'))) & 255
    attrs = span(data, attrs_at, width * height * 4)
    occupied = set()
    placements = []
    counts = Counter()
    for i in range(width * height):
        index, = unpack('<H', attrs, i * 4 + 1)
        if index == 0xffff:
            continue
        if index >= 0xfffb:
            # 0x47de60 blocks in-memory 0xfffb..0xfffd, but the loader's handling of these TNT codes is untraced.
            raise FormatError(f'Reserved TNT feature code {index:#x} requires original loader resolution')
        if index >= len(names):
            raise FormatError('Invalid feature index')
        name = names[index]
        fields = definitions[name]['fields']
        x, z = i % width, i // width
        w, h = int(fields.get('footprintx', '1')), int(fields.get('footprintz', '1'))
        if w < 0 or h < 0:
            raise FormatError('Negative feature footprint: ' + name)
        if x + w > width or z + h > height:
            raise FormatError('Feature crosses map boundary: ' + name)
        # Placement always writes the anchor code, even for a zero-sized footprint.
        footprint = {zz * width + xx for zz in range(z, z + h) for xx in range(x, x + w)} | {i}
        if occupied & footprint:
            raise FormatError('Overlapping feature placement requires original placement resolution: ' + name)
        occupied.update(footprint)
        placements.append(dict(x=x, z=z, width=w, height=h, metal=int(fields.get('metal', '0')),
                               indestructible=bool(int(fields.get('indestructible', '0')) & 1),
                               blocking=bool(blocking_flag(fields))))
        counts[name] += 1
    metal = feature_metal(width, height, bytes([surface]) * (width * height), placements)
    blocking = feature_blocking(width, height, placements)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'metal.bin').write_bytes(metal)
    (output / 'features.bin').write_bytes(blocking)
    provenance = {value['path']: content.provenance[value['path']] for value in definitions.values()}
    metadata = dict(version=1, feature_blocking_version=1, width=width, height=height, surface=surface, features=dict(counts), placements=placements,
                    nonzero_cells=sum(value != 0 for value in metal), values=dict(Counter(metal)),
                    sha256=hashlib.sha256(metal).hexdigest(), tnt_sha256=hashlib.sha256(data).hexdigest(),
                    ota_sha256=hashlib.sha256(ota).hexdigest(), definitions=provenance,
                    blocking_definitions={name: bool(blocking_flag(value['fields'])) for name, value in sorted(definitions.items())},
                    blocking_cells=sum(blocking), blocking_sha256=hashlib.sha256(blocking).hexdigest())
    (output / 'metal.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps({key: metadata[key] for key in ['width', 'height', 'features', 'nonzero_cells', 'values', 'blocking_cells']}, indent=2))


if __name__ == '__main__':
    main()
