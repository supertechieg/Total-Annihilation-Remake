"""Exercise complete original burst-source cleanup, including pool compaction."""
import json
from pathlib import Path
from native_movement_reference import MovementReference, GAME, UNIT, DEFINITION
from native_cob_reference import EXE_HASH

POOL = 0x1500000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(POOL, 0x10000)
    patterns = [[], ['burst'], ['round'], ['other'], ['burst', 'round'], ['round', 'burst'],
                ['burst', 'burst'], ['burst', 'other', 'burst'], ['burst', 'burst', 'burst'],
                ['round', 'burst', 'round', 'burst', 'other']]
    cases = []
    for pattern in patterns:
        native.mu.mem_write(POOL, bytes(0x1000))
        native.write(GAME + 0x141f7, POOL)
        native.write(GAME + 0x141f3, len(pattern))
        native.write(GAME + 0x142f7, 0)
        for index, kind in enumerate(pattern):
            record = POOL + index * 0x6b
            native.write(record, DEFINITION)
            native.write(record + 4, index + 1)
            native.write(record + 0x52, UNIT + 0x118 if kind == 'other' else UNIT)
            native.short(record + 0x60, 0 if kind == 'round' else 3)
        native.call(0x49c880, [UNIT])
        survivors = [native.read(POOL + index * 0x6b + 4) for index in range(native.read(GAME + 0x141f3))]
        cases.append(dict(input=pattern, survivors=survivors))
        # Independent invariants: emitted rounds and other owners are never removed.
        for index, kind in enumerate(pattern):
            if kind != 'burst' and index + 1 not in survivors:
                raise AssertionError(f'Unexpected removal: {pattern}, {survivors}')
        if pattern.count('burst') == 1 and pattern.index('burst') + 1 in survivors:
            raise AssertionError('Single matching burst was not removed')
    adjacent = next(case for case in cases if case['input'] == ['burst', 'burst'])
    if adjacent['survivors'] != [2]:
        raise AssertionError('Expected original adjacent-compaction skip was not observed')
    report = dict(exe_sha256=EXE_HASH, cases=cases,
                  scope='Complete original 0x49c880 and 0x49ae20, no replacement callbacks; no tracked-camera projectile or projectile-to-projectile references',
                  finding='Matching nonzero-burst sources are removed; emitted rounds survive. Adjacent matching sources can be skipped because cleanup increments its index after compaction.')
    Path('analysis/native-burst-cleanup-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'NATIVE_BURST_CLEANUP {len(cases)} scenarios; adjacent-source compaction skip confirmed')


if __name__ == '__main__':
    main()
