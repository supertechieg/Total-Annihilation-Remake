"""Extract the original AI profile scripts and the per-unit AI inputs into local/ai/.

Outputs (all git-ignored, under local/ai/):
  * archives/<archive>/<name>.txt  every ai/*.txt of every archive in PROFILE, byte-exact copies
  * resolved/<name>.txt            one copy per name using the archive precedence below
  * index.json                     sources, SHA-256, unit type table (ids in the native order), per-unit
                                   unitname / category / ai_weight / ai_limit / downloadable strings, and the
                                   console command table read from the executable (for the profile interpreter)

Archive precedence (INFERRED, the same provisional profile tools/prepare_units.py uses for all other
gamedata): rev31.gp3 > btdata.ccx > ccdata.ccx > totala1.hpi. The original resolver order is not verified.
Map .ufo archives (third-party profiles and units such as CorNecro.ufo) are not part of this profile.

Unit type ids (VERIFIED in the disassembly): the FBI loader sorts the definition array from index 1 with the
comparator 0x42db60 = _stricmp(a+0x20, b+0x20) < 0 (0x42d533..0x42d60e) and then writes id = index into
+0x21e (0x42d634). Index 0 is not sorted and is never a valid type. _stricmp 0x4f8a70 in the C locale folds only
A-Z to lower case and compares bytes unsigned. unitname is read at 0x42bfa1 with the TDF string getter
0x4c48c0 into a 0x20-byte field (at most 31 characters); category into a 0x64-byte buffer (99), ai_weight /
ai_limit into 0x40-byte fields +0xbe / +0xfe (63). Which FBI files the original loads (loose files, every
archive, .ufo units) is not verified here; the ids below are for the resolved PROFILE set only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from prepare_units import Content, PROFILE
from tdf import parse

CONSOLE_TABLES = (0x501d38, 0x501f48, 0x501fd0)
# plan/weight/limit are registered separately by 0x406f00 with flags 8 (0x5017a4/0x50179c/0x501794).
PROFILE_COMMANDS = {'plan': 8, 'weight': 8, 'limit': 8}


def stricmp_key(name):
    return bytes(c + 32 if 65 <= c <= 90 else c for c in name.encode('latin-1'))


def console_commands(executable):
    """Read the three {name, handler, flags} tables registered by 0x4195c4..0x4195d8 through 0x4b7760."""
    pe = struct.unpack_from('<I', executable, 0x3c)[0]
    count = struct.unpack_from('<H', executable, pe + 6)[0]
    optional = struct.unpack_from('<H', executable, pe + 20)[0]
    sections = []
    for i in range(count):
        virtual_size, rva, raw_size, raw = struct.unpack_from('<IIII', executable, pe + 24 + optional + i * 40 + 8)
        sections.append((0x400000 + rva, raw, raw_size))

    def offset(address):
        for start, raw, size in sections:
            if start <= address < start + size:
                return raw + address - start
        raise ValueError(hex(address))

    def string(address):
        at = offset(address)
        return executable[at:executable.index(b'\0', at)].decode('latin-1')

    commands = {}
    for table in CONSOLE_TABLES:
        address = table
        while True:
            name, handler, flags = struct.unpack_from('<III', executable, offset(address))
            if not name:
                break
            commands[string(name).lower()] = dict(name=string(name), handler=hex(handler), flags=flags)
            address += 12
    for name, flags in PROFILE_COMMANDS.items():
        commands[name] = dict(name=name, handler=None, flags=flags)
    return commands


def truncate(value, size):
    return value[:size - 1]


def prepare(root, output, executable):
    content = Content(root)
    output.mkdir(parents=True, exist_ok=True)
    sources = {}
    for archive_name in PROFILE:
        archive = content.archives[archive_name]
        folder = output / 'archives' / archive_name.replace('.', '_')
        for path in sorted(archive.entries):
            if path.startswith('ai/') and path.endswith('.txt') and path.count('/') == 1:
                data = archive.extract(path)
                folder.mkdir(parents=True, exist_ok=True)
                (folder / Path(path).name).write_bytes(data)
                sources.setdefault(Path(path).name, []).append(dict(
                    archive=archive_name, path=archive.entries[path].path, sha256=hashlib.sha256(data).hexdigest(),
                    bytes=len(data), lines=data.count(b'\n') + (0 if data.endswith(b'\n') else 1)))
    resolved = {}
    (output / 'resolved').mkdir(exist_ok=True)
    for name, candidates in sorted(sources.items()):
        data = content.read(f'ai/{name}')
        winner = content.provenance[f'ai/{name}']
        (output / 'resolved' / name).write_bytes(data)
        resolved[name] = dict(archive=winner['archive'], sha256=winner['sha256'], bytes=len(data),
                              identical_candidates=sorted({c['sha256'] for c in candidates}) == [winner['sha256']])

    units = []
    for path in sorted(content.paths):
        if not path.startswith('units/') or not path.endswith('.fbi'):
            continue
        fields = parse(content.read(path)).get('unitinfo', {})
        raw_name = fields.get('unitname', '')
        units.append(dict(
            file=path, archive=content.provenance[path]['archive'], sha256=content.provenance[path]['sha256'],
            unitname=truncate(raw_name, 0x20), unitname_truncated=len(raw_name) > 0x1f,
            category=truncate(fields.get('category', ''), 0x64),
            ai_weight=truncate(fields.get('ai_weight', ''), 0x40), ai_limit=truncate(fields.get('ai_limit', ''), 0x40),
            downloadable=fields.get('downloadable'), side=fields.get('side')))
    ordered = sorted(units, key=lambda unit: stricmp_key(unit['unitname']))
    keys = [stricmp_key(unit['unitname']) for unit in ordered]
    duplicates = sorted({unit['unitname'].lower() for unit, key in zip(ordered, keys) if keys.count(key) > 1})
    for type_id, unit in enumerate(ordered, start=1):
        unit['type_id'] = type_id
    commands = console_commands(executable) if executable else None
    index = dict(
        version=1,
        archive_precedence=PROFILE,
        archive_precedence_status='inferred (same provisional profile as prepare_units.py); original resolver not verified',
        profiles=dict(sources=sources, resolved=resolved),
        unit_order=dict(
            rule='type id = 1 + position after sorting by _stricmp(unitname) ascending (0x42d533 sort with comparator '
                 '0x42db60, ids written at 0x42d634); id 0 reserved',
            status='sort/comparator verified in disassembly; the loaded FBI set is the resolved PROFILE set (inferred)',
            type_count_including_zero=len(ordered) + 1,
            case_insensitive_duplicate_unitnames=duplicates),
        units=ordered,
        console_commands=commands,
        console_commands_source=('TotalA.exe tables 0x501d38/0x501f48/0x501fd0 plus 0x406f00 registrations'
                                 if commands else None))
    (output / 'index.json').write_text(json.dumps(index, indent=1), encoding='utf-8')
    return dict(profiles=len(resolved), archive_copies=sum(len(v) for v in sources.values()), units=len(ordered),
                with_ai_weight=sum(1 for u in ordered if u['ai_weight']),
                with_ai_limit=sum(1 for u in ordered if u['ai_limit']), duplicates=duplicates,
                console_commands=len(commands) if commands else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--exe', type=Path, default=Path('local/original/TotalA.exe'))
    parser.add_argument('--output', type=Path, default=Path('local/ai'))
    args = parser.parse_args()
    executable = args.exe.read_bytes() if args.exe.exists() else None
    print('PREPARE_AI', json.dumps(prepare(args.game, args.output, executable)))


if __name__ == '__main__':
    main()
