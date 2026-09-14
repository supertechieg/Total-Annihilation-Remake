"""Build a local original-unit bundle for both factions and construction systems.

The declared archive priority is a provisional content profile, not a claim about
the original archive resolver. Every selected file records its source and hash.
"""
import argparse
import hashlib
import json
from pathlib import Path

from ta_assets import Archive, FormatError, span, unpack
from tdf import parse
from prepare_viewer import model_3do, gaf_entries, gaf_frame
from cob import decode
from weapon_math import weapon_runtime
from movement_definition import movement_definition

PROFILE = ['rev31.gp3', 'btdata.ccx', 'ccdata.ccx', 'totala1.hpi']


class Content:
    def __init__(self, root):
        self.archives = {name: Archive(root / name) for name in PROFILE}
        self.paths = {}
        for name, archive in self.archives.items():
            for path in archive.entries:
                self.paths.setdefault(path.lower(), []).append(name)
        self.provenance = {}

    def read(self, path):
        path = path.lower()
        if path not in self.paths:
            raise FormatError(f'Missing content: {path}')
        archive = self.paths[path][0]
        data = self.archives[archive].extract(path)
        self.provenance[path] = dict(archive=archive, sha256=hashlib.sha256(data).hexdigest(),
                                     bytes=len(data), candidates=self.paths[path])
        return data


def build_menus(content, units):
    side = parse(content.read('gamedata/sidedata.tdf'))
    menus = {}
    for builder, fields in side.get('canbuild', {}).items():
        entries = sorted(((int(key[8:]), value.lower()) for key, value in fields.items()
                          if key.startswith('canbuild') and key[8:].isdigit()))
        menus[builder] = [value for _, value in entries]
    additions = []
    for path in sorted(content.paths):
        if path.startswith('download/') and path.endswith('.tdf'):
            for fields in parse(content.read(path)).values():
                if not isinstance(fields, dict) or 'unitmenu' not in fields or 'unitname' not in fields:
                    continue
                builder, unit = fields['unitmenu'].lower(), fields['unitname'].lower()
                menu = menus.setdefault(builder, [])
                if unit not in menu:
                    menu.append(unit)
                additions.append(dict(builder=builder, unit=unit, menu=fields.get('menu'),
                                      button=fields.get('button'), source=path))
    missing = sorted({unit for builder, entries in menus.items() for unit in [builder, *entries] if unit not in units})
    return menus, additions, missing


def feature_runtime(fields):
    """Loader 0x42245x fields: footprint shorts, height/metal/energy low bits, damage short and the +0xfe flag word."""
    def integer(key, default=0):
        try:
            return int(str(fields.get(key, default)).strip().split()[0])
        except (ValueError, IndexError):
            return default
    return dict(footprintx=integer('footprintx') & 0xffff, footprintz=integer('footprintz') & 0xffff,
                height=integer('height') & 0xff, metal=integer('metal') & 0xffff, energy=integer('energy') & 0xffff,
                damage=integer('damage') & 0xffff, blocking=bool(integer('blocking') & 1), reclaimable=bool(integer('reclaimable') & 1),
                autoreclaimable=bool(integer('autoreclaimable', 1) & 1), indestructible=bool(integer('indestructible') & 1),
                flamable=bool(integer('flamable') & 1), geothermal=bool(integer('geothermal') & 1),
                animating=bool(integer('animating') & 1), animtrans=bool(integer('animtrans') & 1), shadtrans=bool(integer('shadtrans') & 1),
                featuredead=str(fields.get('featuredead', '')).lower(), featurereclamate=str(fields.get('featurereclamate', '')).lower(),
                object=str(fields.get('object', '')).lower())


def gaf_timing(data):
    """GAF entry loop byte (+2) and per-frame durations: the low word of each frame table entry's second dword."""
    count, = unpack('<I', data, 4)
    timing = {}
    for i in range(count):
        at, = unpack('<I', data, 12 + i * 4)
        frames, = unpack('<H', data, at)
        name = span(data, at + 8, 32).split(b'\0', 1)[0].decode('latin-1').lower()
        timing.setdefault(name, dict(loop=data[at + 2], durations=[unpack('<H', data, at + 40 + frame * 8 + 4)[0] for frame in range(frames)]))
    return timing


def feature_sprites(content, output, fields, palette, cache, issues, name):
    """Extract a 2D feature's GAF sequences (anims/<filename>.gaf): every frame of seqname (animating features
    cycle them) and of seqnameshad, each with the GAF frame header x/y offsets."""
    filename = str(fields.get('filename', '')).strip().lower()
    if not filename:
        return None
    path = f'anims/{filename}.gaf'
    if path not in content.paths:
        issues.append(dict(feature=name, missing_gaf=path))
        return None
    if path not in cache:
        data = content.read(path)
        cache[path] = (data, gaf_entries(data), {}, gaf_timing(data))
    data, entries, written, timing = cache[path]
    result = {}
    for key in ['seqname', 'seqnameshad']:
        sequence = str(fields.get(key, '')).strip().lower()
        if not sequence:
            continue
        if sequence not in entries:
            issues.append(dict(feature=name, missing_sequence=f'{path}:{sequence}'))
            continue
        if (sequence, key) not in written:
            frames = []
            # Animating features step the shadow state (+0xd8) like the main one, so every shadow frame is kept.
            offsets = entries[sequence]
            for index, at in enumerate(offsets):
                image, x, y = gaf_frame(data, at, palette)
                digest = hashlib.sha256(f'{path}:{sequence}:{index}'.encode()).hexdigest()[:20]
                image_name = f'features/sprites/{digest}.png'
                image.save(output / image_name)
                frames.append(dict(image=image_name, x=x, y=y, width=image.width, height=image.height))
            written[(sequence, key)] = dict(source=f'{path}:{sequence}', frames=frames, loop=timing[sequence]['loop'],
                                            durations=timing[sequence]['durations'][:len(frames)])
        result['sprite' if key == 'seqname' else 'shadow'] = written[(sequence, key)]
    return result or None


def prepare_features(content, output, required_textures, issues, palette):
    features = {}
    folder = output / 'features'
    folder.mkdir(exist_ok=True)
    (folder / 'sprites').mkdir(exist_ok=True)
    models = {}
    gaf_cache = {}
    for path in sorted(content.paths):
        if not path.startswith('features/') or not path.endswith('.tdf'):
            continue
        for name, fields in parse(content.read(path)).items():
            name = name.lower()
            if not isinstance(fields, dict) or name in features:
                continue
            runtime = feature_runtime(fields)
            entry = dict(source=path, runtime=runtime, model=None, sprites=None)
            if not runtime['object']:
                entry['sprites'] = feature_sprites(content, output, fields, palette, gaf_cache, issues, name)
            model_path = f"objects3d/{runtime['object']}.3do" if runtime['object'] else ''
            if model_path and model_path in content.paths:
                if runtime['object'] not in models:
                    pieces, textures = model_3do(content.read(model_path))
                    filename = f"features/{hashlib.sha256(runtime['object'].encode()).hexdigest()[:20]}.json"
                    (output / filename).write_text(json.dumps(dict(id=runtime['object'], model=dict(pieces=pieces, textures=sorted(textures), source=model_path))), encoding='utf-8')
                    required_textures.update(textures)
                    models[runtime['object']] = filename
                entry['model'] = models[runtime['object']]
            elif model_path:
                issues.append(dict(feature=name, missing_model=model_path))
            features[name] = entry
    return features


def prepare(root, output):
    root = root.resolve(strict=True)
    output = output.resolve()
    if output == root or root in output.parents:
        raise ValueError('Output must be outside the game installation')
    output.mkdir(parents=True, exist_ok=True)
    content = Content(root)
    movement_classes = {fields['name'].lower(): fields for fields in
                        parse(content.read('gamedata/moveinfo.tdf')).values()}
    units = {}
    required_textures = set()
    issues = []
    for path in sorted(content.paths):
        if not path.startswith('units/') or not path.endswith('.fbi'):
            continue
        unit_id = Path(path).stem.lower()
        sections = parse(content.read(path))
        fields = sections.get('unitinfo')
        if not isinstance(fields, dict):
            raise FormatError(f'Missing UNITINFO in {path}')
        folder = output / unit_id
        folder.mkdir(exist_ok=True)
        unit = dict(id=unit_id, name=fields.get('name', unit_id), definition=fields,
                    definition_source=path, model=None, script=None)
        model_path = f"objects3d/{fields.get('objectname', unit_id).lower()}.3do"
        if model_path in content.paths:
            pieces, textures = model_3do(content.read(model_path))
            unit['model'] = dict(pieces=pieces, textures=sorted(textures), source=model_path)
            required_textures.update(textures)
        else:
            issues.append(dict(unit=unit_id, missing_model=model_path))
        script_path = f'scripts/{unit_id}.cob'
        if script_path in content.paths:
            raw = content.read(script_path)
            (folder / 'script.cob').write_bytes(raw)
            try:
                program = decode(raw)
                (folder / 'script.json').write_text(json.dumps(program), encoding='utf-8')
                unit['script'] = f'{unit_id}/script.json'
            except FormatError as error:
                issues.append(dict(unit=unit_id, script_error=str(error)))
        else:
            issues.append(dict(unit=unit_id, missing_script=script_path))
        (folder / 'unit.json').write_text(json.dumps(unit), encoding='utf-8')
        movement_fields = movement_classes.get(fields.get('movementclass', '').lower(), fields)
        units[unit_id] = dict(name=unit['name'], path=f'{unit_id}/unit.json', definition=fields,
                             movement=movement_definition(movement_fields))
    palette_bytes = content.read('palettes/palette.pal')
    if len(palette_bytes) != 1024:
        raise FormatError('Unexpected palette length')
    palette = [channel for i in range(256) for channel in palette_bytes[i * 4:i * 4 + 3]]
    features = prepare_features(content, output, required_textures, issues, palette)
    textures = {}
    texture_folder = output / 'textures'
    texture_folder.mkdir(exist_ok=True)
    for path in sorted(content.paths):
        if not path.startswith('textures/') or not path.endswith('.gaf'):
            continue
        raw = content.read(path)
        for name, frames in gaf_entries(raw).items():
            if name not in required_textures or name in textures:
                continue
            if not frames:
                raise FormatError(f'Texture {name} has no frames')
            image, _, _ = gaf_frame(raw, frames[0], palette)
            filename = hashlib.sha256(name.encode()).hexdigest()[:20] + '.png'
            image.save(texture_folder / filename)
            textures[name] = 'textures/' + filename
    missing_textures = sorted(required_textures - textures.keys())
    menus, additions, missing_menu_units = build_menus(content, units)
    weapons = {}
    for path in sorted(content.paths):
        if path.startswith('weapons/') and path.endswith('.tdf'):
            for name, fields in parse(content.read(path)).items():
                if name in weapons:
                    issues.append(dict(duplicate_weapon=name, previous=weapons[name]['source'], source=path))
                weapons[name] = dict(source=path, definition=fields, runtime=weapon_runtime(fields))
    index = dict(movement_runtime_version=1, weapon_runtime_version=5, feature_runtime_version=5, profile=PROFILE, profile_status='provisional archive precedence', units=units,
                 build_menus=menus, menu_additions=additions, weapons=weapons, features=features, textures=textures,
                 palette=[palette[i:i + 3] for i in range(0, 768, 3)], issues=issues,
                 missing_textures=missing_textures, missing_menu_units=missing_menu_units)
    (output / 'index.json').write_text(json.dumps(index, indent=2), encoding='utf-8')
    (output / 'provenance.json').write_text(json.dumps(content.provenance, indent=2), encoding='utf-8')
    result = dict(units=len(units), builders=len(menus), build_edges=sum(map(len, menus.values())),
                  weapons=len(weapons), textures=len(textures), issues=issues,
                  missing_textures=missing_textures, missing_menu_units=missing_menu_units)
    print(json.dumps(result, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--output', type=Path, default=Path('local/unit-assets'))
    args = parser.parse_args()
    prepare(args.game, args.output)


if __name__ == '__main__':
    main()
