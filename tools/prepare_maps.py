"""Prepare every multiplayer map (an OTA schema of Type Network) into local/maps/<slug>/ with local/maps/index.json.

Each bundle mirrors local/viewer-assets: terrain.png, minimap.png, heights.bin, metal.bin, features.bin, metal.json and
scene.json (environment, start positions). Duplicate map paths resolve by the declared archive order below, which is a
provisional content profile rather than the original resolver. Maps the host cannot load faithfully are listed with a reason.
"""
import argparse
import hashlib
import json
import re
import string
from collections import Counter
from pathlib import Path
from PIL import Image
from ta_assets import Archive, FormatError, span, unpack
from tdf import parse
from prepare_units import Content
from prepare_viewer import tnt_image
from map_environment import environment
from terrain_metal import feature_metal
from feature_blocking import blocking_flag
import map_feature_loader as loader

OFFICIAL = ['totala1.hpi', 'totala2.hpi', 'totala3.hpi', 'totala4.hpi', 'ccmaps.ccx', 'btmaps.ccx'] + [f'tactics{i}.hpi' for i in range(1, 9)]
TERRAIN_LIMIT = 8192


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


SKIRMISH_PLAYERS = 2
NETWORK_TYPES = ['network 1', 'network 2', 'network 3', 'network 4']


def select_schema(descriptor, players=SKIRMISH_PLAYERS):
    """0x436860 modes 2/3: for each type Network 1..4 in order, walk 'Schema 0', 'Schema 1', ... until one is missing;
    a schema whose 'type' (31 characters) matches case-insensitively and has S StartPos specials is taken when
    S != 0 and (S == P or P == 0 or (S > best and best != P)); best persists across types and a later pick replaces
    an earlier one. The port plays two-player skirmishes, so P defaults to 2."""
    chosen, best = None, 0
    for type_name in NETWORK_TYPES:
        index = 0
        while isinstance(descriptor.get(f'schema {index}'), dict):
            schema = descriptor[f'schema {index}']
            index += 1
            if str(schema.get('type', ''))[:0x1f].lower() != type_name:
                continue
            specials = schema.get('specials', {})
            count = sum(1 for special in (specials.values() if isinstance(specials, dict) else [])
                        if isinstance(special, dict) and str(special.get('specialwhat', ''))[:0xf].lower().startswith('startpos'))
            if count and (count == players or players == 0 or (count > best and best != players)):
                chosen, best = schema, count
    return chosen


def network_schema(descriptor):
    return select_schema(descriptor)


def start_positions(schema):
    positions = {}
    for special in schema.get('specials', {}).values():
        if not isinstance(special, dict):
            continue
        what = str(special.get('specialwhat', '')).lower()
        if what.startswith('startpos') and what[8:].isdigit():
            positions[int(what[8:])] = [int(special.get('xpos', '0')), int(special.get('zpos', '0'))]
    return [dict(player=player, x=point[0], z=point[1]) for player, point in sorted(positions.items())]


def loader_definition(name, fields):
    return dict(name=name, footprintx=int(fields.get('footprintx', '1')) & 0xffff, footprintz=int(fields.get('footprintz', '1')) & 0xffff,
                indestructible=bool(int(fields.get('indestructible', '0')) & 1), object=bool(str(fields.get('object', '')).strip()))


def map_features(data, width, height, attrs_at, surface, definitions, schema):
    """Load features as 0x483a99..0x483b4e and 0x423160 do (map_feature_loader), then derive metal and static blocking."""
    header = unpack('<16I', data)
    names = [span(data, header[8] + i * 132 + 4, 128).split(b'\0')[0].decode('latin-1').lower() for i in range(header[7])]
    entries = loader.schema_features(schema)
    wanted = set(names) | {name.lower() for name, _, _ in entries if name}
    missing = sorted(name for name in wanted if name not in definitions)
    if missing:
        raise FormatError(f'feature outside the bundle profile: {missing[0]}')
    for name in wanted:
        if len(definitions[name]['variants']) > 1:
            raise FormatError(f'ambiguous feature definition: {name}')
    loaded = [loader_definition(name, definitions[name]['fields']) for name in names]
    extra = {name: loader_definition(name, definitions[name]['fields']) for name in wanted}
    attrs = span(data, attrs_at, width * height * 4)
    attributes = [unpack('<H', attrs, i * 4 + 1)[0] for i in range(width * height)]
    grid = loader.load(width, height, attributes, loaded, entries, extra)
    names = [definition['name'].lower() for definition in grid.definitions]
    loaded = grid.definitions
    placements = []
    counts = Counter()
    for cell, code in enumerate(grid.codes):
        if code < len(names):
            name = names[code]
            fields = definitions[name]['fields']
            placements.append(dict(name=name, x=cell % width, z=cell // width, width=loader.signed16(loaded[code]['footprintx']),
                                   height=loader.signed16(loaded[code]['footprintz']), metal=int(fields.get('metal', '0')),
                                   indestructible=loaded[code]['indestructible'], blocking=bool(blocking_flag(fields))))
            counts[name] += 1
    voids = [cell for cell, code in enumerate(grid.codes) if code == loader.VOID]
    requested = sum(1 for code in attributes if code < header[7]) + sum(1 for name, _, _ in entries if name)
    metal = feature_metal(width, height, bytes([surface]) * (width * height), [dict(item, width=max(0, item['width']), height=max(0, item['height'])) for item in placements])
    blocking = loader.blocking(grid, [bool(blocking_flag(definitions[name]['fields'])) for name in names])
    return metal, blocking, placements, counts, set(counts), voids, requested, grid.skipped_schema_features


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--output', type=Path, default=Path('local/maps'))
    parser.add_argument('--include-ufo', action='store_true', help='also prepare third-party .ufo maps in the installation')
    parser.add_argument('--only', help='prepare only the map with this slug')
    args = parser.parse_args()
    root = args.game.resolve(strict=True)
    output = args.output.resolve()
    if output == root or root in output.parents:
        parser.error('Output must be outside the installation')
    output.mkdir(parents=True, exist_ok=True)
    content = Content(root)
    palette_bytes = content.read('palettes/palette.pal')
    palette = [channel for i in range(256) for channel in palette_bytes[i * 4:i * 4 + 3]]
    definitions = {}
    for path in sorted(content.paths):
        if path.startswith('features/') and path.endswith('.tdf'):
            for name, fields in parse(content.read(path)).items():
                if isinstance(fields, dict):
                    entry = definitions.setdefault(name.lower(), dict(fields=fields, path=path, variants=set()))
                    entry['variants'].add(json.dumps(fields, sort_keys=True))
    order = OFFICIAL + (sorted(p.name for p in root.iterdir() if p.suffix.lower() == '.ufo') if args.include_ufo else [])
    sources = {}
    for archive_name in order:
        if not (root / archive_name).exists():
            continue
        archive = Archive(root / archive_name)
        for path in archive.entries:
            if path.startswith('maps/') and path.endswith('.tnt') and path[:-4] + '.ota' in archive.entries:
                sources.setdefault(path, []).append((archive_name, archive))
    maps = []
    for path in sorted(sources):
        archive_name, archive = sources[path][0]
        name = Path(path).stem
        key = slug(name)
        if args.only and key != args.only:
            continue
        entry = dict(slug=key, file=name, archive=archive_name, candidates=[item[0] for item in sources[path]])
        try:
            descriptor = parse(archive.extract(path[:-4] + '.ota')).get('globalheader', {})
            schema = network_schema(descriptor)
            if schema is None:
                continue
            # Skirmish menus list maps by file name; archive paths are lower-case, so restore word capitals.
            entry.update(name=string.capwords(name), description=descriptor.get('missiondescription', ''),
                         planet=descriptor.get('planet', ''), players=descriptor.get('numplayers', ''), size=descriptor.get('size', ''))
            data = archive.extract(path)
            header = unpack('<16I', data)
            if header[0] != 0x2000:
                raise FormatError(f'TNT version {header[0]:#x}')
            width, height, attrs_at = header[1], header[2], header[4]
            surface = max(0, int(schema.get('surfacemetal', '-1'))) & 255
            metal, blocking, placements, counts, used, voids, requested, skipped = map_features(data, width, height, attrs_at, surface, definitions, schema)
            starts = start_positions(schema)
            if len(starts) < 2:
                raise FormatError('fewer than two start positions')
            folder = output / key
            folder.mkdir(exist_ok=True)
            scale = 1
            while width * 16 // scale > TERRAIN_LIMIT or height * 16 // scale > TERRAIN_LIMIT:
                scale *= 2
            # Oversized maps paste nearest-sampled tiles directly instead of building the full-resolution image.
            terrain, info, heights = tnt_image(data, palette, scale, max_cells=4096 * 4096)
            info.update(width=width * 16, height=height * 16)
            image = terrain
            terrain.save(folder / 'terrain.png')
            fit = 256 / max(image.width, image.height)
            image.resize((max(1, int(image.width * fit)), max(1, int(image.height * fit))), Image.Resampling.BOX).save(folder / 'minimap.png')
            (folder / 'heights.bin').write_bytes(heights)
            (folder / 'metal.bin').write_bytes(metal)
            (folder / 'features.bin').write_bytes(blocking)
            (folder / 'metal.json').write_text(json.dumps(dict(version=1, feature_blocking_version=1, width=width, height=height, surface=surface,
                features=dict(counts), placements=placements, voids=voids, requested_placements=requested, schema_features=len([e for e in loader.schema_features(schema) if e[0]]),
                skipped_schema_features=skipped, sha256=hashlib.sha256(metal).hexdigest(),
                blocking_cells=sum(blocking), blocking_sha256=hashlib.sha256(blocking).hexdigest(),
                definitions={name: definitions[name]['path'] for name in sorted(used)})), encoding='utf-8')
            info['environment'] = environment(header, descriptor)
            info['environment_version'] = 1
            info.update(name=entry['name'], file=name, archive=archive_name, terrain_scale=scale, start_positions=starts,
                        schema=dict(humanmetal=schema.get('humanmetal'), humanenergy=schema.get('humanenergy'),
                                    computermetal=schema.get('computermetal'), computerenergy=schema.get('computerenergy')),
                        tnt_sha256=hashlib.sha256(data).hexdigest())
            (folder / 'scene.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
            entry.update(supported=True, width=width * 16, height=height * 16, start_positions=len(starts), features=len(placements), voids=len(voids), dropped_placements=requested - len(placements))
        except (FormatError, ValueError, KeyError, IndexError) as error:  # KeyError: a schema feature missing from the definitions (fatal in the original)
            entry.update(supported=False, reason=str(error))
        maps.append(entry)
        print(('OK   ' if entry.get('supported') else 'SKIP ') + key + ('' if entry.get('supported') else ' - ' + entry['reason']), flush=True)
    index_path = output / 'index.json'
    if args.only and index_path.exists():
        previous = [item for item in json.loads(index_path.read_text(encoding='utf-8')).get('maps', []) if item['slug'] != args.only]
        maps = sorted(previous + maps, key=lambda item: item['slug'])
    index = dict(version=2, profile=order, profile_status='provisional archive precedence', maps=maps)
    index_path.write_text(json.dumps(index, indent=2), encoding='utf-8')
    print(json.dumps(dict(maps=len(maps), supported=sum(1 for item in maps if item.get('supported')),
                          reasons=Counter(item['reason'].split(':')[0] for item in maps if not item.get('supported'))), indent=2))


if __name__ == '__main__':
    main()
