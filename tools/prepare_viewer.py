"""Convert an explicit set of original TA assets into a local Godot viewer bundle.

Binary format references are recorded in analysis/ASSET_FORMATS.md.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from PIL import Image
from ta_assets import Archive, FormatError, span, unpack
from cob import decode as decode_cob, disassemble


def text_at(data, offset):
    span(data, offset, 1)
    end = data.find(b'\0', offset)
    if end < 0:
        raise FormatError('Unterminated string')
    return data[offset:end].decode('latin-1')


def model_3do(data):
    seen = set()
    textures = set()
    pieces = []

    def visit(offset, parent, depth):
        while True:
            if offset in seen or depth > 64:
                raise FormatError('Model cycle or excessive depth')
            seen.add(offset)
            version, nv, np, selection, x, y, z, name, _, vp, pp, sibling, child = unpack('<IIIiiiiIIIIII', data, offset)
            if version != 1:
                raise FormatError('Unsupported 3DO version')
            vertices = [list(unpack('<iii', data, vp + i * 12)) for i in range(nv)]
            faces = []
            for index in range(np):
                color, count, _, indices_at, texture_at, _, _, colored = unpack('<8I', data, pp + index * 32)
                indices = list(unpack('<' + 'H' * count, data, indices_at))
                if any(i >= nv for i in indices):
                    raise FormatError('Model vertex index out of bounds')
                if count < 3 or index == selection:
                    continue
                texture = text_at(data, texture_at).lower() if texture_at else None
                if texture:
                    textures.add(texture)
                faces.append(dict(indices=indices, color=color if colored else None, texture=texture))
            piece = dict(name=text_at(data, name), parent=parent, offset=[x, y, z], vertices=vertices, faces=faces)
            piece_index = len(pieces)
            pieces.append(piece)
            if child:
                visit(child, piece_index, depth + 1)
            if not sibling:
                break
            offset = sibling
    visit(0, -1, 0)
    return pieces, textures


def gaf_entries(data):
    version, count, _ = unpack('<III', data)
    if version != 0x10100:
        raise FormatError('Unsupported GAF version')
    result = {}
    for i in range(count):
        at, = unpack('<I', data, 12 + i * 4)
        frames, = unpack('<H', data, at)
        name = span(data, at + 8, 32).split(b'\0', 1)[0].decode('latin-1').lower()
        result[name] = [unpack('<I', data, at + 40 + frame * 8)[0] for frame in range(frames)]
    return result


def gaf_frame(data, at, palette, ancestors=()):
    if at in ancestors or len(ancestors) > 16:
        raise FormatError('GAF frame cycle')
    w, h, x, y, transparent, compressed, subframes, _, pixels_at, _ = unpack('<HHhhBBHIII', data, at)
    if not 0 < w <= 4096 or not 0 < h <= 4096:
        raise FormatError('Invalid GAF image dimensions')
    if subframes:
        canvas = Image.new('RGBA', (w, h))
        for i in range(subframes):
            frame_at, = unpack('<I', data, pixels_at + i * 4)
            layer, lx, ly = gaf_frame(data, frame_at, palette, ancestors + (at,))
            canvas.alpha_composite(layer, (x - lx, y - ly))
        return canvas, x, y
    if not compressed:
        pixels = span(data, pixels_at, w * h)
    else:
        pixels = bytearray([transparent]) * (w * h)
        p = pixels_at
        for row in range(h):
            length, = unpack('<H', data, p)
            p += 2
            stop = p + length
            span(data, p, length)
            column = 0
            while p < stop:
                mask = data[p]
                p += 1
                if mask & 1:
                    count = mask >> 1
                    values = bytes([transparent]) * count
                else:
                    count = (mask >> 2) + 1
                    if mask & 2:
                        if p >= stop:
                            raise FormatError('GAF repeat outside row')
                        values = bytes([data[p]]) * count
                        p += 1
                    else:
                        if p + count > stop:
                            raise FormatError('GAF literal outside row')
                        values = data[p:p + count]
                        p += count
                if column + count > w:
                    raise FormatError('GAF row overflow')
                pixels[row * w + column:row * w + column + count] = values
                column += count
    image = Image.frombytes('P', (w, h), bytes(pixels))
    image.putpalette(palette)
    image.info['transparency'] = transparent
    return image.convert('RGBA'), x, y


def tnt_image(data, palette):
    header = unpack('<16I', data)
    magic, w, h, indices_at, attrs_at, tiles_at, tile_count = header[:7]
    if magic != 0x2000 or w % 2 or h % 2 or not 0 < w * h <= 1024 * 1024:
        raise FormatError('Unsupported TNT map header or excessive dimensions')
    tiles = [Image.frombytes('P', (32, 32), span(data, tiles_at + i * 1024, 1024)) for i in range(tile_count)]
    image = Image.new('P', (w * 16, h * 16))
    image.putpalette(palette)
    for row in range(h // 2):
        for col in range(w // 2):
            tile, = unpack('<H', data, indices_at + (row * (w // 2) + col) * 2)
            if tile >= len(tiles):
                raise FormatError('TNT tile index out of bounds')
            image.paste(tiles[tile], (col * 32, row * 32))
    heights = span(data, attrs_at, w * h * 4)[::4]
    return image, dict(width=w * 16, height=h * 16, tiles=tile_count, sea_level=header[9],
                      height_grid_width=w, height_grid_height=h), heights


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--output', type=Path, default=Path('local/viewer-assets'))
    args = parser.parse_args()
    output = args.output.resolve()
    root = args.game.resolve(strict=True)
    if root == output or root in output.parents:
        parser.error('Output must be outside installation')
    output.mkdir(parents=True, exist_ok=True)
    archives = {}
    provenance = []

    def asset(archive, path):
        if archive not in archives:
            archives[archive] = Archive(root / archive)
        data = archives[archive].extract(path)
        provenance.append(dict(archive=archive, path=path, sha256=hashlib.sha256(data).hexdigest(), bytes=len(data)))
        return data

    palette_bytes = asset('totala1.hpi', 'palettes/palette.pal')
    if len(palette_bytes) != 1024:
        raise FormatError('Expected 256 RGBA palette entries')
    palette = [channel for i in range(256) for channel in palette_bytes[i * 4:i * 4 + 3]]
    pieces, needed = model_3do(asset('totala1.hpi', 'objects3d/armcom.3do'))
    resolved = {}
    base = archives['totala1.hpi']
    for path in sorted(base.entries):
        if not path.startswith('textures/') or not path.endswith('.gaf'):
            continue
        data = asset('totala1.hpi', path)
        for name, frames in gaf_entries(data).items():
            if name not in needed:
                continue
            if not frames:
                raise FormatError('Texture without frames')
            image, _, _ = gaf_frame(data, frames[0], palette)
            filename = f'texture_{len(resolved):03d}.png'
            image.save(output / filename)
            resolved[name] = filename
    if needed - resolved.keys():
        raise FormatError(f'Missing model textures: {needed - resolved.keys()}')
    definition = asset('rev31.gp3', 'units/armcom.fbi').decode('latin-1')
    script = asset('totala1.hpi', 'scripts/armcom.bos').decode('latin-1').replace('\r', '')
    (output / 'armcom.bos').write_text(script, encoding='utf-8')
    fields = dict((k.lower(), v.strip()) for k, v in re.findall(r'(\w+)\s*=\s*([^;]*);', definition))
    (output / 'armcom.fbi').write_text(definition, encoding='utf-8')
    unit = dict(id='armcom', name=fields.get('name', 'Arm Commander'), description=fields.get('description', ''),
                pieces=pieces, textures=resolved, palette=[palette[i:i + 3] for i in range(0, 768, 3)],
                definition=fields, scale_divisor=65536)
    (output / 'unit.json').write_text(json.dumps(unit), encoding='utf-8')
    compiled_script = asset('rev31.gp3', 'scripts/armcom.cob')
    script_program = decode_cob(compiled_script)
    script_program['source'] = 'rev31.gp3:scripts/ARMCOM.COB'
    model_names = {piece['name'].lower() for piece in pieces}
    if any(name.lower() not in model_names for name in script_program['pieces']):
        raise FormatError('COB piece not found in Commander model')
    (output / 'armcom.cob').write_bytes(compiled_script)
    (output / 'armcom.cob.json').write_text(json.dumps(script_program), encoding='utf-8')
    (output / 'armcom.cob.asm').write_text(disassemble(script_program), encoding='utf-8')
    image, map_info, heights = tnt_image(asset('ccmaps.ccx', 'maps/comet catcher.tnt'), palette)
    image.save(output / 'terrain.png')
    image.copy().resize((384, 480), Image.Resampling.NEAREST).save(output / 'minimap.png')
    (output / 'heights.bin').write_bytes(heights)
    map_info.update(name='Comet Catcher', archive='ccmaps.ccx', unit='armcom',
                    notice='Original COB script playback. Projection, rotation order, and texture orientation still need comparison against the original renderer.')
    (output / 'scene.json').write_text(json.dumps(map_info, indent=2), encoding='utf-8')
    (output / 'provenance.json').write_text(json.dumps(provenance, indent=2), encoding='utf-8')
    print(json.dumps(dict(map=map_info, pieces=len(pieces), faces=sum(len(p['faces']) for p in pieces),
                          textures=len(resolved), sources=len(provenance)), indent=2))


if __name__ == '__main__':
    main()
