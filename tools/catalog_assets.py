"""Index all installed TA archives without assuming load precedence."""
import argparse
from collections import Counter
import json
from pathlib import Path
from ta_assets import Archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('installation', type=Path)
    parser.add_argument('--output', type=Path, default=Path('local/assets/catalog.json'))
    args = parser.parse_args()
    root = args.installation.resolve(strict=True)
    output = args.output.resolve()
    if output == root or root in output.parents:
        parser.error('Output must be outside the game installation')
    result = []
    extensions = Counter()
    for file in sorted(root.iterdir()):
        if file.suffix.lower() not in ('.hpi', '.ccx', '.ufo', '.gp3'):
            continue
        archive = Archive(file)
        for entry in archive.entries.values():
            extensions[Path(entry.path).suffix.lower()] += 1
            result.append(dict(archive=file.name, path=entry.path, size=entry.size,
                               compression=entry.compression))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(dict(assets=len(result), extensions=dict(extensions)), indent=2))


if __name__ == '__main__':
    main()
