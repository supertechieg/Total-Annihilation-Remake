"""Prepare locally installed weapon WAV sounds without distributing game data."""
import argparse
import io
import json
import wave
from pathlib import Path
from prepare_units import Content


def prepare(game, output):
    game = game.resolve(strict=True)
    output = output.resolve()
    if output == game or game in output.parents:
        raise ValueError('Output must be outside the game installation')
    index = json.loads(Path('local/unit-assets/index.json').read_text())
    content = Content(game)
    names = sorted({str(item['definition'][field]).lower() for item in index['weapons'].values()
                    for field in ('soundstart', 'soundhit', 'soundwater') if item['definition'].get(field)})
    output.mkdir(parents=True, exist_ok=True)
    sounds, missing = {}, []
    for name in names:
        if '/' in name or '\\' in name or name in ('.', '..'):
            raise ValueError(f'Invalid sound name: {name}')
        path = 'sounds/' + name + '.wav'
        if path not in content.paths:
            missing.append(name)
            continue
        data = content.read(path)
        with wave.open(io.BytesIO(data), 'rb') as wav:
            metadata = dict(channels=wav.getnchannels(), sample_width=wav.getsampwidth(),
                            rate=wav.getframerate(), frames=wav.getnframes())
        (output / (name + '.wav')).write_bytes(data)
        sounds[name] = dict(**metadata, **content.provenance[path])
    report = dict(sounds=sounds, missing=missing)
    (output / 'index.json').write_text(json.dumps(report, indent=2))
    print(f'WEAPON_SOUNDS {len(sounds)} prepared; missing={missing}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--output', type=Path, default=Path('local/weapon-sounds'))
    args = parser.parse_args()
    prepare(args.game, args.output)
