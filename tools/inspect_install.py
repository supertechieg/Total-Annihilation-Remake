"""Read-only installation inventory and PE32 inspection; Python standard library only."""
import argparse
import hashlib
import json
import re
import struct
from collections import Counter
from pathlib import Path


def inspect_pe(data):
    def u16(offset):
        return struct.unpack_from('<H', data, offset)[0]

    def u32(offset):
        return struct.unpack_from('<I', data, offset)[0]

    pe = u32(0x3c)
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Invalid PE signature')
    opt = pe + 24
    if u16(opt) != 0x10b:
        raise ValueError('This inspector supports PE32 only')
    sections = []
    for index in range(u16(pe + 6)):
        p = opt + u16(pe + 20) + index * 40
        sections.append(dict(name=data[p:p + 8].rstrip(b'\0').decode('ascii'),
                             virtual_size=u32(p + 8), rva=u32(p + 12),
                             raw_size=u32(p + 16), raw_offset=u32(p + 20)))

    def offset(rva):
        for section in sections:
            delta = rva - section['rva']
            if 0 <= delta < section['raw_size']:
                return section['raw_offset'] + delta
        if 0 <= rva < u32(opt + 60):
            return rva
        raise ValueError(f'Unmapped file RVA: {rva:x}')

    def cstr(p):
        return data[p:data.index(b'\0', p)].decode('ascii', errors='replace')

    imports = {}
    import_rva = u32(opt + 104)
    if import_rva:
        p = offset(import_rva)
        while any(data[p:p + 20]):
            thunk, _, _, name, first = struct.unpack_from('<5I', data, p)
            dll = cstr(offset(name))
            functions = []
            t = offset(thunk or first)
            while u32(t):
                value = u32(t)
                functions.append(f'ordinal:{value & 0xffff}' if value & 0x80000000
                                 else cstr(offset(value) + 2))
                t += 4
            imports[dll] = functions
            p += 20
    return dict(machine=hex(u16(pe + 4)), image_base=hex(u32(opt + 28)),
                entry_point=hex(u32(opt + 28) + u32(opt + 16)),
                sections=sections, imports=imports)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('installation', type=Path)
    parser.add_argument('--output', type=Path, default=Path('analysis'))
    args = parser.parse_args()
    root = args.installation.resolve(strict=True)
    out = args.output.resolve()
    if out == root or root in out.parents:
        parser.error('Output must be outside the installation')
    out.mkdir(parents=True, exist_ok=True)
    files = []
    executables = {}
    for path in sorted(root.rglob('*')):
        if not path.is_file():
            continue
        sha = hashlib.sha256()
        with path.open('rb') as stream:
            header = stream.read(20)
            sha.update(header)
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                sha.update(block)
        relative = path.relative_to(root).as_posix()
        files.append(dict(path=relative, size=path.stat().st_size,
                          sha256=sha.hexdigest(), header_hex=header.hex()))
        if path.suffix.lower() in ('.exe', '.dll'):
            executables[relative] = inspect_pe(path.read_bytes())
    (out / 'inventory.json').write_text(json.dumps(files, indent=2), encoding='utf-8')
    (out / 'executables.json').write_text(json.dumps(executables, indent=2), encoding='utf-8')
    data = (root / 'TotalA.exe').read_bytes()
    strings = [f'{match.start():08x}\t{match.group().decode("ascii")}'
               for match in re.finditer(rb'[\x20-\x7e]{6,}', data)]
    (out / 'totala-strings.tsv').write_text('\n'.join(strings) + '\n', encoding='utf-8')
    counts = Counter(Path(item['path']).suffix.lower() for item in files)
    summary = dict(files=len(files), bytes=sum(item['size'] for item in files),
                   extensions=dict(counts), engine=executables['TotalA.exe'])
    (out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(json.dumps(dict(files=summary['files'], bytes=summary['bytes'],
                          extensions=summary['extensions'], engine=summary['engine']), indent=2))


if __name__ == '__main__':
    main()
