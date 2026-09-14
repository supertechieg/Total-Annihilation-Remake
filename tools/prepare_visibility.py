"""Extract the original line-of-sight assets into local/visibility/.

gamedata/LOS.TDF is copied raw. anims/VISMASKS.GAF sequence 'vismask' is decoded to
raw palette indices (no palette conversion). Every archive copy of each file is
hashed; the selected copy follows the provisional prepare_units PROFILE precedence.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path

from ta_assets import FormatError, span, unpack
from tdf import parse
from prepare_units import PROFILE, Content

LOS_TDF = 'gamedata/los.tdf'
VISMASKS = 'anims/vismasks.gaf'


def copies(content, path):
    """Hash every archive copy; return (selected bytes, provenance record)."""
    data = content.read(path)
    record = dict(content.provenance[path.lower()])
    hashes = {}
    for name in content.paths[path.lower()]:
        blob = content.archives[name].extract(path.lower())
        hashes[name] = dict(sha256=hashlib.sha256(blob).hexdigest(), bytes=len(blob))
    record['copies'] = hashes
    record['all_copies_identical'] = len({h['sha256'] for h in hashes.values()}) == 1
    record['selection_rule'] = 'first archive in PROFILE order (provisional precedence)'
    return data, record


def gaf_sequences(data):
    """Sequence table; accepts header version 0x10100 and the version-0 header VISMASKS.GAF ships with."""
    version, count, _ = unpack('<III', data)
    if version not in (0, 0x10100):
        raise FormatError(f'Unsupported GAF version {version:#x}')
    result = {}
    for i in range(count):
        at, = unpack('<I', data, 12 + i * 4)
        frames, = unpack('<H', data, at)
        name = span(data, at + 8, 32).split(b'\0', 1)[0].decode('latin-1').lower()
        result[name] = [unpack('<I', data, at + 40 + frame * 8)[0] for frame in range(frames)]
    return version, result


def gaf_raw_frame(data, at, ancestors=()):
    if at in ancestors or len(ancestors) > 16:
        raise FormatError('GAF frame cycle')
    w, h, x, y, transparent, compressed, subframes, unknown, pixels_at, unknown2 = unpack('<HHhhBBHIII', data, at)
    if not 0 < w <= 4096 or not 0 < h <= 4096:
        raise FormatError('Invalid GAF image dimensions')
    frame = dict(width=w, height=h, xoff=x, yoff=y, transparent=transparent, compressed=compressed,
                 subframes=subframes, header_unknown=[unknown, unknown2], offset=at)
    if subframes:
        frame['children'] = [gaf_raw_frame(data, unpack('<I', data, pixels_at + i * 4)[0], ancestors + (at,))
                             for i in range(subframes)]
        return frame
    if not compressed:
        pixels = bytes(span(data, pixels_at, w * h))
    else:
        out = bytearray([transparent]) * (w * h)
        p = pixels_at
        for row in range(h):
            length, = unpack('<H', data, p)
            p += 2
            stop = p + length
            span(data, p, length)
            column = 0
            while p < stop:
                mask = data[p]
                p += 1
                if mask & 1:
                    count = mask >> 1
                    values = bytes([transparent]) * count
                else:
                    count = (mask >> 2) + 1
                    if mask & 2:
                        if p >= stop:
                            raise FormatError('GAF repeat outside row')
                        values = bytes([data[p]]) * count
                        p += 1
                    else:
                        if p + count > stop:
                            raise FormatError('GAF literal outside row')
                        values = data[p:p + count]
                        p += count
                if column + count > w:
                    raise FormatError('GAF row overflow')
                out[row * w + column:row * w + column + count] = values
                column += count
        pixels = bytes(out)
    frame['opaque_pixels'] = sum(1 for v in pixels if v != transparent)
    frame['pixel_values'] = sorted(set(pixels))
    frame['pixels_sha256'] = hashlib.sha256(pixels).hexdigest()
    frame['pixels_base64'] = base64.b64encode(pixels).decode('ascii')
    return frame


def table_info(tdf):
    info = tdf.get('tableinfo')
    if not isinstance(info, dict) or 'numtables' not in info:
        raise FormatError('LOS.TDF lacks TABLEINFO.numtables')
    numtables = int(info['numtables'])
    tables = []
    for i in range(1, numtables + 1):
        sec = tdf.get(f'table{i}')
        if not isinstance(sec, dict):
            tables.append(dict(table=i, present=False))
            continue
        numlines = int(sec.get('numlines', 0))
        present = sum(1 for j in range(1, numlines + 1) if f'line{j}' in sec)
        tables.append(dict(table=i, present=True, numlines=numlines, lines_present=present))
    return numtables, tables


def prepare(root, output):
    content = Content(root)
    output.mkdir(parents=True, exist_ok=True)

    los, los_record = copies(content, LOS_TDF)
    (output / 'los.tdf').write_bytes(los)
    numtables, tables = table_info(parse(los))

    gaf, gaf_record = copies(content, VISMASKS)
    gaf_version, sequences = gaf_sequences(gaf)
    if 'vismask' not in sequences:
        raise FormatError(f'VISMASKS.GAF lacks vismask sequence: {sorted(sequences)}')
    frames = []
    for index, at in enumerate(sequences['vismask']):
        frame = gaf_raw_frame(gaf, at)
        frame['index'] = index
        frames.append(frame)
    vismasks = dict(version=1, source=gaf_record, gaf_header_version=gaf_version, sequence='vismask', sequences=sorted(sequences),
                    pixel_encoding='base64 raw palette indices, row-major', frames=frames)
    (output / 'vismasks.json').write_text(json.dumps(vismasks, indent=1))

    index = dict(version=1, profile=PROFILE, profile_status='provisional archive precedence',
                 sources={LOS_TDF: los_record, VISMASKS: gaf_record},
                 los=dict(file='los.tdf', sha256=los_record['sha256'], numtables=numtables, tables=tables),
                 vismasks=dict(file='vismasks.json', sha256=gaf_record['sha256'], sequence='vismask',
                               frame_count=len(frames),
                               frames=[dict(index=f['index'], width=f['width'], height=f['height'], xoff=f['xoff'],
                                            yoff=f['yoff'], transparent=f['transparent'], subframes=f['subframes'],
                                            opaque_pixels=f.get('opaque_pixels')) for f in frames]))
    (output / 'index.json').write_text(json.dumps(index, indent=1))
    return index


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    parser.add_argument('--output', type=Path, default=Path('local/visibility'))
    args = parser.parse_args()
    print(json.dumps(prepare(args.game, args.output), indent=1))


if __name__ == '__main__':
    main()
