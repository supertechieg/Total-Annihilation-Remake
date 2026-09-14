"""Execute original feature placement 0x423c50 and removal 0x4246b0 over TNT attribute grids, driven in the
loader's two-pass order (0x483a99..0x483b4e), followed by the unmodified OTA schema feature pass 0x423160, for random
grids and every official multiplayer map.

0x423160 runs natively over a descriptor list at +0xdbc/+0xdc0; its by-name definition loader 0x4224b0 is replaced by a
recorder that appends the requested definition (as the original appends and returns the old count), and a null cell
passed to 0x423c50 (an anchor outside the map, undefined in the original) is recorded and skipped.

Model-instance creation 0x45a8d0/0x45aaa0, geothermal effects 0x472c50 and the pathing refresh 0x440a40 are stubbed;
the 0x800-record instance pool is linked as 0x421f20 initializes it.
"""
import base64
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH, STOP, STACK_TOP, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX
from ta_assets import Archive, unpack, span
from tdf import parse
from prepare_units import Content
from prepare_maps import OFFICIAL, network_schema, slug
from map_feature_loader import schema_features

REGION = 0x2000000
POOL = REGION
DEFINITIONS = REGION + 0x20000
GRID = 0x3000000
DESCRIPTOR = REGION + 0x40000
ENTRIES = REGION + 0x41000


def definition_bytes(definition):
    flags = (0 if definition['object'] else 1) | (0x40 if definition.get('blocking') else 0) | (0x200 if definition['indestructible'] else 0)
    data = bytearray(0x100)
    name = definition.get('name', '').encode('latin-1')[:0x7f]
    data[:len(name)] = name
    data[0x94:0x98] = struct.pack('<HH', definition['footprintx'] & 0xffff, definition['footprintz'] & 0xffff)
    data[0xfe:0x100] = struct.pack('<H', flags)
    return bytes(data)


class Loader:
    def __init__(self):
        self.native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
        mu = self.native.mu
        mu.mem_map(REGION, 0x200000)
        mu.mem_map(GRID, 0x2000000)
        mu.mem_write(0x45a8d0, b'\xb8\x01\x00\x00\x00\xc2\x04\x00')
        mu.mem_write(0x45aaa0, b'\xc2\x04\x00')
        mu.mem_write(0x472c50, b'\xc2\x08\x00')
        mu.mem_write(0x440a40, b'\xc2\x08\x00')
        mu.mem_write(0x4224b0, b'\xc2\x04\x00')
        self.extra = {}
        self.loaded = []
        self.null_cells = 0
        mu.hook_add(UC_HOOK_CODE, self.load_definition, begin=0x4224b0, end=0x4224b0)
        mu.hook_add(UC_HOOK_CODE, self.null_placement, begin=0x423c50, end=0x423c50)

    def load_definition(self, mu, address, size, data):
        native = self.native
        sp = mu.reg_read(UC_X86_REG_ESP)
        name = bytes(mu.mem_read(native.read(sp + 4), 0x80)).split(b'\0')[0].decode('latin-1')
        count = native.read(GAME + 0x14253)
        mu.mem_write(DEFINITIONS + count * 0x100, definition_bytes(dict(self.extra[name.lower()], name=name)))
        native.write(GAME + 0x14253, count + 1)
        self.loaded.append(name)
        mu.reg_write(UC_X86_REG_EAX, count)

    def null_placement(self, mu, address, size, data):
        native = self.native
        sp = mu.reg_read(UC_X86_REG_ESP)
        if native.read(sp + 4) == 0:
            self.null_cells += 1
            mu.reg_write(UC_X86_REG_EAX, 0)
            mu.reg_write(UC_X86_REG_ESP, sp + 0x18)
            mu.reg_write(UC_X86_REG_EIP, native.read(sp))

    def place(self, cell, code):
        # Direct stdcall entry without the shared helper's instruction-count and timeout instrumentation.
        native = self.native
        sp = STACK_TOP - 24
        for offset, value in enumerate([STOP, cell, code, 0, 0, 10]):
            native.write(sp + offset * 4, value)
        native.mu.reg_write(UC_X86_REG_ESP, sp)
        native.mu.emu_start(0x423c50, STOP)
        if native.mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError('Placement did not return')

    def run(self, width, height, attributes, definitions, entries=(), extra=None):
        native, mu = self.native, self.native.mu
        count = width * height
        native.write(GAME + 0x14233, width)
        native.write(GAME + 0x14237, height)
        native.write(GAME + 0x14287, GRID)
        native.write(GAME + 0x1426f, DEFINITIONS)
        native.write(GAME + 0x14253, len(definitions))
        cells = bytearray(count * 13)
        for i in range(count):
            cells[i * 13 + 8:i * 13 + 10] = b'\xff\xff'
        mu.mem_write(GRID, bytes(cells))
        pool = bytearray(0x18000)
        for i in range(0x800):
            struct.pack_into('<hh', pool, i * 48, i + 1 if i < 0x7ff else -1, i - 1)
        mu.mem_write(POOL, bytes(pool))
        native.write(GAME + 0x1420b, POOL)
        native.write(GAME + 0x14213, 0xffffffff)
        native.write(GAME + 0x14217, 0xffffffff)
        native.write(GAME + 0x1421b, 0)
        mu.mem_write(DEFINITIONS, b''.join(definition_bytes(item) for item in definitions))
        for cell, code in enumerate(attributes):
            if code == 0xfffc:
                self.place(GRID + cell * 13, 0xfffc)
        for cell, code in enumerate(attributes):
            if code < len(definitions):
                self.place(GRID + cell * 13, code)
        self.extra = extra or {}
        self.loaded = []
        self.null_cells = 0
        native.write(GAME + 0x391e9, DESCRIPTOR)
        native.write(DESCRIPTOR + 0xdbc, ENTRIES)
        native.write(DESCRIPTOR + 0xdc0, len(entries))
        for index, (name, x, z) in enumerate(entries):
            record = bytearray(0x88)
            encoded = name.encode('latin-1')[:0x7f]
            record[:len(encoded)] = encoded
            struct.pack_into('<ii', record, 0x80, x, z)
            mu.mem_write(ENTRIES + index * 0x88, bytes(record))
        self.call(0x423160, [])
        data = bytes(mu.mem_read(GRID, count * 13))
        codes = b''.join(data[i * 13 + 8:i * 13 + 10] for i in range(count))
        offsets = b''.join(data[i * 13 + 10:i * 13 + 12] for i in range(count))
        bits = bytes(data[i * 13 + 12] & 1 for i in range(count))
        return dict(codes=base64.b64encode(codes).decode(), offsets=base64.b64encode(offsets).decode(), bits=base64.b64encode(bits).decode(),
                    loaded=list(self.loaded), null_cells=self.null_cells)

    def call(self, address, args):
        native = self.native
        sp = STACK_TOP - 4 * (len(args) + 1)
        for offset, value in enumerate([STOP] + list(args)):
            native.write(sp + offset * 4, value)
        native.mu.reg_write(UC_X86_REG_ESP, sp)
        native.mu.emu_start(address, STOP)
        if native.mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError(f'Call {address:#x} did not return')


def random_cases(loader):
    rng = random.Random(0x423c50)
    cases = []
    for index in range(300):
        width, height = rng.randrange(4, 24), rng.randrange(4, 24)
        definitions = [dict(name=f'Feat{i}', footprintx=rng.choice([0, 1, 1, 2, 2, 3, 4, 5, -1]), footprintz=rng.choice([0, 1, 1, 2, 3, 4, -1]),
                            indestructible=rng.randrange(5) == 0, object=rng.randrange(3) != 0, blocking=rng.randrange(2) == 1)
                       for i in range(rng.randrange(1, 8))]
        extra = {f'extra{i}': dict(name=f'Extra{i}', footprintx=rng.choice([1, 2, 3, 4, 5, -3]) & 0xffff, footprintz=rng.choice([1, 2, 3, -5]) & 0xffff,
                                   indestructible=rng.randrange(4) == 0, object=rng.randrange(2) == 0, blocking=True) for i in range(3)}
        entries = []
        for _ in range(rng.randrange(0, 12)):
            name = rng.choice([d['name'] for d in definitions] + [e['name'] for e in extra.values()] + [''])
            name = ''.join(ch.upper() if rng.randrange(2) else ch.lower() for ch in name)
            entries.append((name, rng.randrange(-3, width + 3), rng.randrange(-3, height + 3)))
        extra.update({d['name'].lower(): d for d in definitions})
        attributes = []
        for _ in range(width * height):
            roll = rng.random()
            if roll < 0.62:
                attributes.append(0xffff)
            elif roll < 0.86:
                attributes.append(rng.randrange(len(definitions)))
            else:
                attributes.append(rng.choice([0xfffc, 0xfffc, 0xfffe, 0xfffd, 0xfffb, len(definitions), len(definitions) + 3]))
        cases.append(dict(width=width, height=height, attributes=attributes, definitions=definitions, entries=entries, extra=extra,
                          native=loader.run(width, height, attributes, [dict(item, footprintx=item['footprintx'] & 0xffff, footprintz=item['footprintz'] & 0xffff) for item in definitions], entries, extra)))
    # Instance pool exhaustion: 3,000 one-cell object features.
    attributes = [0] * 3000 + [0xffff] * (64 * 64 - 3000)
    definitions = [dict(footprintx=1, footprintz=1, indestructible=False, object=True, blocking=False)]
    cases.append(dict(width=64, height=64, attributes=attributes, definitions=definitions, native=loader.run(64, 64, attributes, definitions)))
    return cases


def map_cases(loader, root):
    content = Content(root)
    tdf = {}
    for path in sorted(content.paths):
        if path.startswith('features/') and path.endswith('.tdf'):
            for name, fields in parse(content.read(path)).items():
                if isinstance(fields, dict):
                    tdf.setdefault(name.lower(), fields)
    seen = set()
    cases = []
    for archive_name in OFFICIAL:
        if not (root / archive_name).exists():
            continue
        archive = Archive(root / archive_name)
        for path in sorted(archive.entries):
            if not (path.startswith('maps/') and path.endswith('.tnt')) or path in seen or path[:-4] + '.ota' not in archive.entries:
                continue
            seen.add(path)
            if network_schema(parse(archive.extract(path[:-4] + '.ota')).get('globalheader', {})) is None:
                continue
            data = archive.extract(path)
            header = unpack('<16I', data)
            if header[0] != 0x2000:
                continue
            width, height = header[1], header[2]
            if width * height * 13 > 0x2000000 or width % 2 or height % 2:
                print('SKIP', path, width, height, flush=True)
                continue
            names = [span(data, header[8] + i * 132 + 4, 128).split(b'\0')[0].decode('latin-1').lower() for i in range(header[7])]
            if any(name not in tdf for name in names):
                continue
            schema = network_schema(parse(archive.extract(path[:-4] + '.ota')).get('globalheader', {}))
            entries = schema_features(schema)
            if any(name.lower() not in tdf for name, _, _ in entries if name):
                continue
            definitions = []
            for name in names + sorted({name.lower() for name, _, _ in entries if name} - set(names)):
                fields = tdf[name]
                definitions.append(dict(name=name, footprintx=int(fields.get('footprintx', '1')) & 0xffff, footprintz=int(fields.get('footprintz', '1')) & 0xffff,
                                        indestructible=bool(int(fields.get('indestructible', '0')) & 1), object=bool(str(fields.get('object', '')).strip()),
                                        blocking=bool(int(fields.get('blocking', '0')) & 1)))
            attrs = span(data, header[4], width * height * 4)
            attributes = [unpack('<H', attrs, i * 4 + 1)[0] for i in range(width * height)]
            extra = {item['name']: item for item in definitions}
            definitions = definitions[:len(names)]
            cases.append(dict(map=slug(Path(path).stem), width=width, height=height, attributes=base64.b64encode(struct.pack(f'<{len(attributes)}H', *attributes)).decode(),
                              definitions=definitions, entries=entries, extra=extra, native=loader.run(width, height, attributes, definitions, entries, extra)))
            print('MAP', cases[-1]['map'], width, height, len(names), flush=True)
    return cases


def main():
    loader = Loader()
    random_list = random_cases(loader)
    maps = map_cases(loader, Path(r'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'))
    folder = Path('local/features')
    folder.mkdir(exist_ok=True)
    (folder / 'native-map-features.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, random=random_list, maps=maps)))
    print(f'NATIVE_MAP_FEATURES {len(random_list)} random grids, {len(maps)} official maps')


if __name__ == '__main__':
    main()
