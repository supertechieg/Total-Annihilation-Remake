"""Extract original weapon explosion frames into ignored local content."""
import argparse
import hashlib
import json
from pathlib import Path
from prepare_units import Content
from prepare_viewer import gaf_entries, gaf_frame


def prepare(game, output):
    game = game.resolve(strict=True)
    output = output.resolve()
    if output == game or game in output.parents:
        raise ValueError('Output must be outside the game installation')
    content = Content(game)
    index = json.loads(Path('local/unit-assets/index.json').read_text())
    palette_raw = content.read('palettes/palette.pal')
    palette = [value for i in range(256) for value in palette_raw[i * 4:i * 4 + 3]]
    requested = set()
    for weapon in index['weapons'].values():
        fields = weapon['definition']
        for prefix in ('', 'water', 'lava'):
            archive, art = fields.get(prefix + 'explosiongaf'), fields.get(prefix + 'explosionart')
            if archive and art:
                requested.add((archive.lower(), art.lower()))
    output.mkdir(parents=True, exist_ok=True)
    effects, missing = {}, []
    for archive, art in sorted(requested):
        key = archive + '/' + art
        path = 'anims/' + archive + '.gaf'
        if path not in content.paths:
            missing.append(key)
            continue
        data = content.read(path)
        entries = gaf_entries(data)
        if art not in entries:
            missing.append(key)
            continue
        frames = []
        for number, address in enumerate(entries[art]):
            image, x, y = gaf_frame(data, address, palette)
            filename = hashlib.sha256(key.encode()).hexdigest()[:16] + f'-{number:03}.png'
            image.save(output / filename)
            frames.append(dict(file=filename, width=image.width, height=image.height, x=x, y=y))
        effects[key] = dict(frames=frames, source=content.provenance[path])
    (output / 'index.json').write_text(json.dumps(dict(effects=effects, missing=missing), indent=2))
    print(f'WEAPON_EFFECTS {len(effects)} animations, {sum(len(e["frames"]) for e in effects.values())} frames; missing={missing}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--output', type=Path, default=Path('local/weapon-effects'))
    args = parser.parse_args()
    prepare(args.game, args.output)
