"""Audit every installed Commander COB copy before choosing a script for playback."""
import argparse
import hashlib
import json
from pathlib import Path
from ta_assets import Archive
from cob import decode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    args = parser.parse_args()
    copies = []
    for path in sorted(args.game.iterdir()):
        if path.suffix.lower() not in ('.gp3', '.ccx', '.ufo', '.hpi'):
            continue
        archive = Archive(path)
        if 'scripts/armcom.cob' in archive.entries:
            data = archive.extract('scripts/armcom.cob')
            script = decode(data)
            copies.append(dict(archive=path.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                               functions=len(script['functions']), pieces=len(script['pieces'])))
    loose = args.game / 'scripts/armcom.cob'
    if loose.exists():
        data = loose.read_bytes()
        copies.append(dict(archive='loose scripts/armcom.cob', bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    identical = bool(copies) and len({item['sha256'] for item in copies}) == 1
    report = dict(copies=copies, identical=identical, loose_override=loose.exists(),
                  archive_precedence='Not required to distinguish these copies when identical; general precedence remains separate work.')
    output = Path('analysis/commander-script-audit.json')
    output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    if not identical:
        raise SystemExit('Commander variants differ; resolve active source before assuming equivalence.')


if __name__ == '__main__':
    main()
