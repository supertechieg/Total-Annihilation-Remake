"""Oracle O5: execute the original visibility queries 0x465ac0, 0x4658e0 and 0x408090 in Unicorn.

All three routines run unmodified and call nothing except 0x465ac0 -> 0x408090 (native). No stubs.
Decoded from the disassembly (tadis.py 0x465ac0 0x465e20, 0x4658e0 0x465ab5, 0x408090 0x4080ff):

  0x408090 stdcall(rec, P16*) ret 8: mapped-only probe. col = s16(hiword P.x)>>5,
      row = (s16(hiword P.z) - (s16(hiword P.y)>>1))>>5, unsigned bounds vs rec+0x80/+0x84,
      returns bit (1 << byte game+0x2a43) of word [game+0x14273][2*(row*w2+col)] (the LOCAL player's bit).
      It never looks at game+0x14281. Callers: 0x465ac0 (LOS-off probes), 0x407fbd, 0x49bf2f.
  0x465ac0 stdcall(rec, unit) ret 8: owner (unit+0x96 == rec) -> 1; unit+0x10e & 4 -> 0;
      P0 = pos + (def+0x15e, def+0x16e, def+0x166); unless unit+0x110 & 0x200, P0.y < sea<<16 (signed) -> 0;
      probes P0, P1 = P0+(d176,0,0), P2 = P1+(0,-d17a,d17e), P3 = P2-(d176,0,0). Each probe re-reads the byte
      game+0x14281 & 2: set -> rec+0x7c byte grid != 0, clear -> call 0x408090 (last probe inlines it).
  0x4658e0 stdcall(rec, col, row, fpx, fpz, h) ret 0x18: A = (s16(col<<4), s16(row<<4) - (s16(h)>>1)),
      B = (s16((col<<4)+(fpx<<4)), s16((row<<4)+(fpz<<4)) - (s16(h)>>1)); the subtraction is 32-bit after sign
      extension (not wrapped to 16 bits); cell = (X>>5, Z>>5); mode from word game+0x14281 & 2.

The def extents are confirmed by the loader at 0x42d0cb: +0x176 = +0x16a-+0x15e, +0x17a = +0x16e-+0x162,
+0x17e = +0x172-+0x166 (max - min per axis), and at 0x42d079 min x/z = trunc(-footprint<<20 / 2).
"""
import base64
import json
from pathlib import Path
import random
import struct

from native_movement_reference import MovementReference, GAME, UNIT, DEFINITION
from native_cob_reference import EXE_HASH, STOP, STACK_TOP
from unicorn.x86_const import (UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX,
                               UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP)

GRIDS = 0x2000000
MAPPED = 0x2800000
POINT = 0x3000000
PLAYERS = 4
REC_SIZE = 0x14b
CALLS_PER_SCENE = 250
SCENES_PER_MODE = 24  # 6000 calls per mode

VIS_FIELDS = ['rec', 'owner', 'state10e', 'flags110', 'x', 'y', 'z', 'd15e', 'd16e', 'd166', 'd176', 'd17a', 'd17e', 'result']
FEATURE_FIELDS = ['rec', 'col', 'row', 'fpx', 'fpz', 'h', 'result']
PROBE_FIELDS = ['rec', 'x', 'y', 'z', 'result']


def rec_address(index):
    return GAME + 0x1b63 + index * REC_SIZE


def s32(v):
    v &= 0xffffffff
    return v - (1 << 32) if v & 0x80000000 else v


class QueryOracle:
    def __init__(self):
        self.native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
        mu = self.native.mu
        mu.mem_map(GRIDS, 0x800000)
        mu.mem_map(MAPPED, 0x800000)
        mu.mem_map(POINT, 0x1000)
        self.rng = random.Random(0x465ac0)

    def stdcall(self, address, args):
        native, mu = self.native, self.native.mu
        sp = STACK_TOP - (len(args) + 1) * 4
        native.write(sp, STOP)
        for i, value in enumerate(args):
            native.write(sp + 4 + i * 4, value)
        mu.reg_write(UC_X86_REG_ESP, sp)
        # Garbage in every register shows nothing depends on caller state.
        for reg in (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP):
            mu.reg_write(reg, self.rng.getrandbits(32))
        mu.emu_start(address, STOP, count=100000)
        if mu.reg_read(UC_X86_REG_EIP) != STOP or mu.reg_read(UC_X86_REG_ESP) != sp + 4 + 4 * len(args):
            raise RuntimeError(f'{address:#x} did not return with stdcall cleanup')
        return mu.reg_read(UC_X86_REG_EAX)

    def load_scene(self, scene):
        native, mu = self.native, self.native.mu
        w2, h2 = scene['w2'], scene['h2']
        native.write(GAME + 0x14281, (native.read(GAME + 0x14281) & ~0xffff) | scene['flags'])
        mu.mem_write(GAME + 0x1427f, bytes([scene['sea_level']]))
        mu.mem_write(GAME + 0x2a43, bytes([scene['local_player']]))
        mapped = base64.b64decode(scene['mapped'])
        mu.mem_write(MAPPED, mapped + self.rng.randbytes(64))
        native.write(GAME + 0x14273, MAPPED)
        for i, rec in enumerate(scene['recs']):
            base = rec_address(i)
            grid = base64.b64decode(rec['los'])
            mu.mem_write(GRIDS + i * 0x100000, grid + self.rng.randbytes(64))
            native.write(base, 1)
            mu.mem_write(base + 0x146, bytes([rec['index']]))
            native.write(base + 0x7c, GRIDS + i * 0x100000)
            native.write(base + 0x80, w2)
            native.write(base + 0x84, h2)
            native.write(base + 0x88, (w2 * h2 + 7) & ~7)

    def visible(self, call):
        native, mu = self.native, self.native.mu
        owner = rec_address(call['owner']) if call['owner'] >= 0 else rec_address(PLAYERS + 2)
        native.write(UNIT + 0x96, owner)
        native.write(UNIT + 0x92, DEFINITION)
        mu.mem_write(UNIT + 0x10e, bytes([call['state10e']]))
        native.write(UNIT + 0x110, call['flags110'])
        for offset, key in ((0x6a, 'x'), (0x6e, 'y'), (0x72, 'z')):
            native.write(UNIT + offset, call[key])
        for key in ('d15e', 'd16e', 'd166', 'd176', 'd17a', 'd17e'):
            native.write(DEFINITION + int(key[1:], 16), call[key])
        return self.stdcall(0x465ac0, [rec_address(call['rec']), UNIT])

    def feature(self, call):
        return self.stdcall(0x4658e0, [rec_address(call['rec']), call['col'], call['row'], call['fpx'], call['fpz'], call['h']])

    def probe(self, call):
        self.native.mu.mem_write(POINT, struct.pack('<III', call['x'], call['y'], call['z']))
        return self.stdcall(0x408090, [rec_address(call['rec']), POINT])


def make_scene(rng, mode):
    edges = mode.endswith('edges')
    roll = rng.random()
    w2 = rng.randrange(1, 6) if roll < 0.2 else rng.randrange(1, 40) if roll < 0.8 else rng.randrange(40, 130)
    h2 = rng.randrange(1, 6) if rng.random() < 0.2 else rng.randrange(1, 40) if rng.random() < 0.8 else rng.randrange(40, 130)
    if 'tall' in mode:
        w2, h2 = rng.randrange(1, 4), rng.randrange(1100, 1700)
    count = w2 * h2
    pad = (count + 7) & ~7
    flags = rng.getrandbits(16)
    los_on = rng.random() < 0.5
    if '_los_on' in mode:
        los_on = True
    if '_los_off' in mode or '_nonlocal' in mode or 'mapping_off' in mode:
        los_on = False
    flags = (flags | 2) if los_on else (flags & ~2)
    mapping_off = 'mapping_off' in mode or (not edges and rng.random() < 0.15)
    if 'mapping_off' in mode:
        flags &= ~1
    local = rng.randrange(PLAYERS)
    if edges and rng.random() < 0.3:
        local = rng.choice([10, 15, 16, 17, 31, 32, 33, 200, 255])
    recs = []
    for i in range(PLAYERS):
        density = rng.choice([0.0, 0.05, 0.3, 0.6, 0.95, 1.0])
        los = bytes((rng.randrange(1, 256) if rng.random() < 0.3 else 1) if rng.random() < density else 0 for _ in range(pad))
        recs.append(dict(index=i, los=base64.b64encode(los).decode()))
    words = []
    density = rng.choice([0.05, 0.3, 0.5, 0.8, 0.97])
    for _ in range(count):
        if mapping_off:
            words.append(0xffff)
        else:
            w = 0
            for bit in range(16):
                if rng.random() < density:
                    w |= 1 << bit
            words.append(w)
    mapped = struct.pack(f'<{count}H', *words)
    return dict(mode=mode, w2=w2, h2=h2, flags=flags, sea_level=rng.choice([0, 0, 1, 40, 100, 255, rng.randrange(256)]),
                local_player=local, mapped=base64.b64encode(mapped).decode(), recs=recs)


def pick_rec(rng, scene, mode):
    local = scene['local_player']
    if '_nonlocal' in mode:
        return rng.choice([i for i in range(PLAYERS) if i != local])
    if '_los_off' in mode and local < PLAYERS:
        return local
    return rng.randrange(PLAYERS)


def coord16(rng, low_px, high_px):
    return (rng.randrange(low_px, high_px) << 16) + rng.randrange(65536)


def make_visible(rng, scene, mode):
    w2, h2 = scene['w2'], scene['h2']
    rec = pick_rec(rng, scene, mode)
    owner = rng.choice([-1, -1, -1, 0, 1, 2, 3])
    if rng.random() < 0.08:
        owner = rec
    state = rng.getrandbits(8) & ~4
    if 'cloaked' in mode:
        state |= 4 if rng.random() < 0.7 else 0
    elif rng.random() < 0.05:
        state |= 4
    flags110 = rng.getrandbits(32)
    if 'below_sea' not in mode and 'edges' not in mode:
        flags110 = flags110 | 0x200 if rng.random() < 0.5 else flags110
    if rng.random() < 0.7:
        fx, fz = rng.randrange(0, 9), rng.randrange(0, 9)
        height = rng.randrange(0, 80 << 16)
        lower = [s32((-fx << 20) // 2 if fx else 0), 0, s32((-fz << 20) // 2 if fz else 0)]
        upper = [fx * 524288, height, fz * 524288]
        bounds = [lower[0], upper[1], lower[2], upper[0] - lower[0], upper[1] - lower[1], upper[2] - lower[2]]
    else:
        bounds = [rng.randrange(-(96 << 16), 96 << 16) for _ in range(6)]
    sea = scene['sea_level']
    if 'below_sea' in mode:
        y = ((sea << 16) - bounds[1]) + rng.randrange(-(3 << 16), 3 << 16)
        if rng.random() < 0.1:
            y = (sea << 16) - bounds[1] + rng.choice([-1, 0, 1])
    else:
        y = coord16(rng, -40, 300)
    if 'edges' in mode:
        roll = rng.random()
        if roll < 0.35:
            x = coord16(rng, -80, 64) if rng.random() < 0.5 else coord16(rng, w2 * 32 - 64, w2 * 32 + 64)
            z = coord16(rng, -80, 64) if rng.random() < 0.5 else coord16(rng, h2 * 32 - 64, h2 * 32 + 200)
            y = coord16(rng, -300, 300)
        elif roll < 0.6:
            x = coord16(rng, 32700, 32768) if rng.random() < 0.5 else coord16(rng, -32768, -32700)
            z = coord16(rng, 32600, 32768) if rng.random() < 0.5 else coord16(rng, -32768, -32600)
            y = coord16(rng, -32768, 32768)
        else:
            x, y, z = rng.getrandbits(32), rng.getrandbits(32), rng.getrandbits(32)
            if rng.random() < 0.5:
                bounds = [rng.getrandbits(32) for _ in range(6)]
    else:
        x = coord16(rng, -48, w2 * 32 + 48)
        z = coord16(rng, -48, h2 * 32 + 48) + (y >> 1)
    if 'tall' in mode:
        # Row = s16(z) - (s16(y)>>1) beyond the int16 range: only a >1024-row grid can tell 32-bit from wrapped math.
        flags110 |= 0x200
        x = coord16(rng, -8, w2 * 32 + 8)
        y = coord16(rng, -32768, -4000)
        z = coord16(rng, 30000, 32768)
    return dict(rec=rec, owner=owner, state10e=state, flags110=flags110 & 0xffffffff, x=x & 0xffffffff, y=y & 0xffffffff,
                z=z & 0xffffffff, d15e=bounds[0] & 0xffffffff, d16e=bounds[1] & 0xffffffff, d166=bounds[2] & 0xffffffff,
                d176=bounds[3] & 0xffffffff, d17a=bounds[4] & 0xffffffff, d17e=bounds[5] & 0xffffffff)


def make_feature(rng, scene, mode):
    w2, h2 = scene['w2'], scene['h2']
    rec = pick_rec(rng, scene, mode)
    if 'edges' in mode and rng.random() < 0.5:
        values = [rng.getrandbits(32) for _ in range(5)]
        if rng.random() < 0.5:  # near the 16-bit wrap of col<<4
            values[0] = rng.choice([2047, 2048, 2049, 4095, 4096, -2049, -2048, 0x7fff, 0x8000]) & 0xffffffff
            values[1] = rng.choice([2047, 2048, 2049, 4095, 4096, -2049, -2048, 0x7fff, 0x8000]) & 0xffffffff
        col, row, fpx, fpz, h = values
    else:
        col = rng.randrange(-6, w2 * 2 + 6)
        row = rng.randrange(-6, h2 * 2 + 12)
        fpx, fpz = rng.randrange(0, 9), rng.randrange(0, 9)
        h = rng.randrange(0, 256)
        if 'edges' in mode:
            fpx, fpz = rng.randrange(-8, 40), rng.randrange(-8, 40)
            h = rng.randrange(-600, 600)
    if 'wrap16' in mode:
        # B = s16(col<<4) + s16(fpx<<4) wraps around 16 bits: both halves near -32768 land back inside the grid,
        # so a port that adds the sign-extended halves without wrapping reads out of bounds instead.
        def near_min(limit):
            return (0x800 + rng.randrange(0, max(1, limit)) + rng.choice([0, 0x1000, -0x1000, 0x7ffff000])) & 0xffffffff
        if rng.random() < 0.8:
            col, fpx = near_min(w2), near_min(w2)
        if rng.random() < 0.8:
            row, fpz = near_min(h2), near_min(h2)
            h = rng.randrange(-64, 64)
    if 'tall' in mode:
        col = rng.randrange(-2, w2 * 2 + 2)
        row = rng.randrange(1850, 2049)
        h = rng.randrange(-32768, 0)
    return dict(rec=rec, col=col & 0xffffffff, row=row & 0xffffffff, fpx=fpx & 0xffffffff, fpz=fpz & 0xffffffff, h=h & 0xffffffff)


def make_probe(rng, scene, mode):
    w2, h2 = scene['w2'], scene['h2']
    rec = pick_rec(rng, scene, mode)
    if 'edges' in mode and rng.random() < 0.5:
        x, y, z = rng.getrandbits(32), rng.getrandbits(32), rng.getrandbits(32)
    else:
        y = coord16(rng, -300, 300)
        x = coord16(rng, -64, w2 * 32 + 64)
        z = coord16(rng, -64, h2 * 32 + 64) + (y >> 1)
    if 'tall' in mode:
        x = coord16(rng, -8, w2 * 32 + 8)
        y = coord16(rng, -32768, -4000)
        z = coord16(rng, 30000, 32768)
    return dict(rec=rec, x=x & 0xffffffff, y=y & 0xffffffff, z=z & 0xffffffff)


MODES = {
    'visible_los_on': ('visible', make_visible, VIS_FIELDS),
    'visible_los_off_local': ('visible', make_visible, VIS_FIELDS),
    'visible_nonlocal_los_off': ('visible', make_visible, VIS_FIELDS),
    'visible_mapping_off': ('visible', make_visible, VIS_FIELDS),
    'visible_cloaked': ('visible', make_visible, VIS_FIELDS),
    'visible_below_sea': ('visible', make_visible, VIS_FIELDS),
    'visible_edges': ('visible', make_visible, VIS_FIELDS),
    'feature_los_on': ('feature', make_feature, FEATURE_FIELDS),
    'feature_los_off_local': ('feature', make_feature, FEATURE_FIELDS),
    'feature_nonlocal_los_off': ('feature', make_feature, FEATURE_FIELDS),
    'feature_mapping_off': ('feature', make_feature, FEATURE_FIELDS),
    'feature_edges': ('feature', make_feature, FEATURE_FIELDS),
    'visible_tall_grid': ('visible', make_visible, VIS_FIELDS),
    'feature_tall_grid': ('feature', make_feature, FEATURE_FIELDS),
    'probe_408090_tall_grid': ('probe', make_probe, PROBE_FIELDS),
    'probe_408090_local': ('probe', make_probe, PROBE_FIELDS),
    'probe_408090_nonlocal': ('probe', make_probe, PROBE_FIELDS),
    'probe_408090_edges': ('probe', make_probe, PROBE_FIELDS),
    'feature_wrap16': ('feature', make_feature, FEATURE_FIELDS),
}


def main():
    oracle = QueryOracle()
    rng = random.Random(20260914)
    output = []
    summary = {}
    for mode, (kind, generator, fields) in MODES.items():
        runner = getattr(oracle, kind)
        true_count = 0
        total = 0
        for _ in range(SCENES_PER_MODE):
            scene = make_scene(rng, mode)
            oracle.load_scene(scene)
            rows = []
            for _ in range(CALLS_PER_SCENE):
                call = generator(rng, scene, mode)
                result = runner(call)
                if result not in (0, 1):
                    raise AssertionError(f'{mode}: non-boolean result {result:#x}')
                call['result'] = result
                true_count += result
                total += 1
                rows.append([call[f] for f in fields])
            scene['kind'] = kind
            scene['fields'] = fields
            scene['calls'] = rows
            output.append(scene)
        summary[mode] = dict(calls=total, true=true_count)
        print(f'MODE {mode} calls={total} true={true_count}', flush=True)
    folder = Path('local/visibility')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native-visibility-query.json').write_text(json.dumps(dict(
        version=1, exe_sha256=EXE_HASH, routines=['0x465ac0', '0x4658e0', '0x408090'], stubs={},
        rec_layout={'+0x7c': 'LOS byte grid ptr', '+0x80': 'w2', '+0x84': 'h2', '+0x146': 'player index'},
        game_layout={'+0x14281': 'mode flags word', '+0x1427f': 'sea level byte', '+0x2a43': 'local player byte', '+0x14273': 'mapped word buffer ptr'},
        owner_note='owner -1 = a record pointer that is not any tested rec', summary=summary, scenes=output)), encoding='utf-8')
    print(f'NATIVE_VISIBILITY_QUERY {sum(v["calls"] for v in summary.values())} calls in {len(output)} scenes, {len(MODES)} modes')


if __name__ == '__main__':
    main()
