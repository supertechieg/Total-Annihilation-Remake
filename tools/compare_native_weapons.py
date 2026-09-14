"""Compare reconstructed numeric conversions with the original weapon loader."""
import json
from pathlib import Path
from weapon_math import scaled_weapon_value, minimum_barrel_angle


def main():
    folder = Path('local/weapons')
    reference = json.loads((folder / 'native-conversions.json').read_text())
    differences = []
    for item in reference['cases']:
        actual = minimum_barrel_angle(item['value']) if item['kind'] == 'minimum_angle' else scaled_weapon_value(item['value'], item['kind'])
        if actual != item['result']:
            differences.append(dict(**item, actual=actual))
    report = dict(cases=len(reference['cases']), mismatches=len(differences), exe_sha256=reference['exe_sha256'],
                  scope='Weapon velocity, start velocity, acceleration, turn rate, reload, burst-rate, beam duration and minimum barrel angle text conversion for 193 bundled definitions plus supplied boundary cases; excludes firing schedule and projectile simulation', differences=differences)
    (folder / 'native-comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f"NATIVE_WEAPON_COMPARISON {report['cases'] - len(differences)} / {report['cases']} cases match")
    print(differences[:5])
    raise SystemExit(bool(differences))


if __name__ == '__main__':
    main()
