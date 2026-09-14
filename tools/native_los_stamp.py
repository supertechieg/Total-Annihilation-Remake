"""Oracle O3: execute the original LOS stamping routines on fuzzed unit lifecycles.

Routines run unmodified in Unicorn (every address below is entered at its first instruction):
  0x482ac0(unit)            unit LOS create            (callers 0x486178, 0x486312)
  0x4827b0(unit)            per-unit LOS update        (-> 0x4825b0 ctx update)
  0x482090(unit)            death LOS removal          (caller 0x486845, gated by flags & 2 at 0x486832)
  0x482910(pos, sight, eye, duration)  temporary death LOS (caller 0x486748, gated at 0x486706/0x48672a)
  0x482130()                temporary LOS expiry       (caller 0x495688)
  0x4816a0(resetMapping)    full LOS rebuild
  and everything they call: 0x482270 add, 0x481d50 remove, 0x481930 map, 0x4825b0, the ray-object accessors
  0x433500/0x433520/0x4335c0/0x4335e0/0x4339c0/0x4339e0 and the GAF frame lookup 0x4b7f30.

Native inputs are built from real data:
  * Ray object 0x51e6a0: loaded by the ORIGINAL loader 0x433130 from local/visibility/los.tdf (tools/native_los_tables.py
    LosLoader, reused by import in the same emulator).
  * Height grid game+0x1428f: built by the ORIGINAL 0x482c20 from real map heights (local/maps/<map>/heights.bin, whole map
    or a sub-rectangle), exactly as tools/native_los_heights.py does.
  * Vismask sequence game+0x1485b: {u16 count; frame pointers at +0x28 + 8*i}; frames {u16 w, u16 h, s16 xoff, s16 yoff,
    u8 transparent, +0x10 pixel pointer} from local/visibility/vismasks.json (anims/vismasks.gaf "vismask"). These are the
    only fields 0x4b7f30 and the stamp routines read (0x4b7f30: [seq+0] count, [seq+0x28+8*i]; stamps: +0,+2,+4,+6,+8,+0x10).

Stubs (none of them is LOS logic):
  * 0x4b4f10 operator new wrapper / 0x4b4f20 delete wrapper: only reached from 0x482c20 (height-grid build); bump
    allocator / no-op, as in native_los_heights.py.
  * 0x466c20 minimap terrain redraw and 0x466dc0 minimap unit dots, both called only at the end of 0x4816a0: `ret` plus a
    call counter. They paint minimap surfaces that are not set up here. Observable side effect NOT reproduced: 0x466c20
    consumes the redraw bit (game+0x142f1: if bit 4 then clear bit 4, set bit 2). The recorded dirty byte is therefore the
    value handed to the minimap, before it consumes it; the port exposes the same "requested" bit.
  * Harness-level caller gates (not stubbed code, replicated in Python from the disassembly): death at 0x486706
    (unit+0x110 & 0x10000000), 0x48672a (owner index == game+0x2a43) -> 0x482910(unit+0x6a, movsx def+0x202,
    movsx word def+0x170, 60); then 0x486832 (flags & 2) -> 0x482090(unit). The dead unit's word +0xa6 is then cleared so
    later rebuilds skip it (the real clearing site is outside this oracle).

Documented assumptions:
  * True LOS with trunc(sight/32) <= 0 indexes table -1 (0x433500 decrements): the 16 bytes before the table vector are an
    object outside the vector. The oracle writes zeros there, i.e. an empty ray vector: only the centre cell is stamped.
    In the shipped game that memory belongs to the heap and its content is unknown.
  * The temporary LOS array (game+0x1427b, 20 entries of 0x24 bytes) starts zeroed; its origin field +0x20 is never
    initialised by 0x482910, so stale values from earlier (compacted) entries are observable and compared.
  * A native access violation (e.g. 0x4b7f30 returning NULL for a remove with a slot >= frame count after a True->Circular
    switch) ends the sequence; the fault step is recorded and must be reproduced by the port.

Per step the recorded state is: sha256 (first 16 hex) of every player's full padded LOS byte grid, of the full mapped word
buffer and of the 20 temp entries' canonical text; unit +0x7a/+0x7c/+0xf8 for every unit slot; temp count; flags word
game+0x14281; dirty byte game+0x142f1; the two minimap stub call counts.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import random
import struct

from native_los_tables import LosLoader
from native_movement_reference import GAME
from native_cob_reference import EXE_HASH, UC_HOOK_CODE
from unicorn import UcError
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_EBX, UC_X86_REG_EDX

RAYS = 0x51e6a0
REGION = 0x4000000
CELLS = REGION
HG_HEAP = REGION + 0x400000
HG_HEAP_SIZE = 0x200000
VIS = REGION + 0x600000
MAPPED = REGION + 0x610000
LOS_BASE = REGION + 0x650000
UNITS = REGION + 0x800000
DEFS = REGION + 0x810000
TEMP = REGION + 0x830000
UNIT_SIZE = 0x118
REC_BASE = GAME + 0x1b63
REC_SIZE = 0x14b
PLAYER_SLOTS = 10
TEMP_CAPACITY = 20
TEMP_SIZE = 0x24
TICK = 0x38a47


def s16(v):
    return ((v & 0xffff) ^ 0x8000) - 0x8000


def s32(v):
    return ((v & 0xffffffff) ^ 0x80000000) - 0x80000000


def h16(data):
    return hashlib.sha256(data).hexdigest()[:16]


class StampOracle:
    def __init__(self, executable, cob, tdf, vismasks):
        self.loader = LosLoader(executable, cob)
        loaded = self.loader.load(tdf)
        if 'fault' in loaded:
            raise SystemExit(f'los.tdf failed to load natively: {loaded["fault"]}')
        self.tables = loaded['tables']
        self.native = native = self.loader.native
        self.mu = mu = native.mu
        mu.mem_map(REGION, 0x1000000)
        mu.mem_write(0x4b4f10, b'\xc3')
        mu.mem_write(0x4b4f20, b'\xc3')
        mu.hook_add(UC_HOOK_CODE, self._allocate, begin=0x4b4f10, end=0x4b4f10)
        self.minimap_calls = [0, 0]
        for index, address in enumerate((0x466c20, 0x466dc0)):
            mu.mem_write(address, b'\xc3')
            mu.hook_add(UC_HOOK_CODE, self._minimap, begin=address, end=address, user_data=index)
        begin = native.read(RAYS + 4)
        self.table_begin = begin
        mu.mem_write(begin - 16, bytes(16))
        # vismask sequence
        frames = vismasks['frames']
        seq = VIS
        mu.mem_write(seq, bytes(0x28 + 8 * len(frames)))
        mu.mem_write(seq, struct.pack('<H', len(frames)))
        cursor = VIS + 0x1000
        for i, frame in enumerate(frames):
            pixels = base64.b64decode(frame['pixels_base64'])
            assert len(pixels) == frame['width'] * frame['height']
            header = struct.pack('<HHhhB7xI', frame['width'], frame['height'], frame['xoff'], frame['yoff'], frame['transparent'], cursor + 0x20)
            mu.mem_write(cursor, header + bytes(0x20 - len(header)) + pixels)
            native.write(seq + 0x28 + 8 * i, cursor)
            cursor = (cursor + 0x20 + len(pixels) + 15) & ~15
        self.frame_count = len(frames)
        self.heap = HG_HEAP
        # Observation-only coverage probes (no state is changed): address -> (name, predicate on registers/stack)
        self.coverage = {}
        esp = lambda m: m.reg_read(UC_X86_REG_ESP)
        probes = {
            0x4822ec: ('add_true', None), 0x4824d9: ('add_circular', None),
            0x481fb9: ('remove_circular', None),
            0x48199f: ('map_true', None), 0x481bc3: ('map_circular', None),
            0x48262b: ('true_early_out', lambda m: s32(m.reg_read(UC_X86_REG_EAX)) <= 5),
            0x482649: ('true_update_after_no_early_out', None),
            0x48262e: ('true_early_out_with_slot_zero', lambda m: s32(m.reg_read(UC_X86_REG_EAX)) <= 5 and self.byte(esp(m) + 0x18) == 0),
            0x48263c: ('true_remove_before_update', None),
            0x4826a9: ('true_out_of_height_grid', None),
            0x482744: ('circular_early_out', lambda m: m.reg_read(UC_X86_REG_EDX) == m.reg_read(UC_X86_REG_EBX)),
            0x433500: ('table_minus_one_read', lambda m: self.native.read(esp(m) + 4) & 0xffff == 0),
            0x4821ea: ('temp_compaction_copy', None),
            # Hook fires before `cmp eax, 0x14`, after eax = temp count was loaded at 0x482926 (the earlier probe at
            # 0x482926 tested a stale eax and counted garbage).
            0x48292c: ('temp_add_attempt_at_capacity', lambda m: s32(m.reg_read(UC_X86_REG_EAX)) >= 20),
            0x482935: ('temp_add_accepted', None),
            0x4829f3: ('temp_add_true', None),
            0x481dcc: ('remove_true', None),
            0x481fc8: ('circular_remove_slot_ge_frame_count', lambda m: m.reg_read(UC_X86_REG_EDX) >= self.frame_count),
            # true stamp ray loops: steps, steps inside the height grid, visible cells, horizon raises
            0x4823fc: ('add_true_ray_step', None), 0x48243a: ('add_true_ray_step_in_grid', None),
            0x48246c: ('add_true_ray_visible_cell', None), 0x48248e: ('add_true_horizon_raise', None),
            0x481f4c: ('remove_true_ray_visible_cell', None), 0x481b43: ('map_true_ray_visible_cell', None),
            0x481b6b: ('map_true_ray_bit_newly_set', None), 0x481a5d: ('map_true_centre_bit_newly_set', None),
            # circular clipping (add / remove / map): right, bottom, left, top, and non-empty rectangle
            0x4824fc: ('add_circular_clip_right', None), 0x48251d: ('add_circular_clip_bottom', None),
            0x48252b: ('add_circular_clip_left', None), 0x482537: ('add_circular_clip_top', None),
            0x482549: ('add_circular_nonempty', None),
            0x481fdc: ('remove_circular_clip_right', None), 0x481ffd: ('remove_circular_clip_bottom', None),
            0x48200b: ('remove_circular_clip_left', None), 0x482017: ('remove_circular_clip_top', None),
            0x482029: ('remove_circular_nonempty', None),
            0x481c14: ('map_circular_clip_right', None), 0x481c2c: ('map_circular_clip_bottom', None),
            0x481c44: ('map_circular_clip_left', None), 0x481c54: ('map_circular_clip_top', None),
            0x481c76: ('map_circular_nonempty', None), 0x481cd8: ('map_circular_bit_newly_set', None),
            # rebuild / ctx update / expiry branches
            0x4816af: ('rebuild_reset_mapping', None), 0x481734: ('rebuild_player_refill', None),
            0x48181a: ('rebuild_unit_los_on', None), 0x481831: ('rebuild_unit_true', None),
            0x48275c: ('circular_update_los_on', None), 0x48277c: ('circular_update_los_off', None),
            0x48279a: ('circular_update_map', None), 0x482682: ('true_update_add', None), 0x48269b: ('true_update_map', None),
            0x482187: ('temp_compaction_entered', None), 0x4821bf: ('temp_compaction_found_expired', None),
            0x482160: ('temp_expired_remove', None),
            0x481d2d: ('map_changed_local_redraw', None),
            0x4818e6: ('rebuild_circular_map', None),
            0x482a94: ('temp_circular_map', None),
            0x482c08: ('create_circular_map', None),
        }
        for address, (name, predicate) in probes.items():
            self.coverage[name] = 0
            mu.hook_add(UC_HOOK_CODE, self._probe, begin=address, end=address, user_data=(name, predicate))
        more = [
            (0x481930, 'map_circular_with_mapping_off', lambda m: (self.word(GAME + 0x14281) & 5) == 0),
            # 4825b0 true early-out with slot 0 called from the temp add (return address 0x4829f9 at esp+0x14 after its
            # five pushes): the stale entry origin +0x20 suppresses the registration.
            (0x48262e, 'temp_true_stale_origin_early_out', lambda m: s32(m.reg_read(UC_X86_REG_EAX)) <= 5 and self.byte(esp(m) + 0x18) == 0 and self.native.read(esp(m) + 0x14) == 0x4829f9),
            # 0x481d50 true mode entered from 0x482090 (return 0x482109 at esp+0x48) with stored slot 0.
            (0x481dcc, 'death_remove_true_with_slot_zero', lambda m: self.native.read(esp(m) + 0x48) == 0x482109 and self.byte(self.native.read(m.reg_read(UC_X86_REG_EBX) + 0xc)) == 0),
            # removals by caller (return address at esp+0x48 at both mode dispatch targets): expiry 0x482166, death 0x482109.
            (0x481fb9, 'expiry_remove_circular', lambda m: self.native.read(esp(m) + 0x48) == 0x482166),
            (0x481dcc, 'expiry_remove_true', lambda m: self.native.read(esp(m) + 0x48) == 0x482166),
            (0x481fb9, 'death_remove_circular', lambda m: self.native.read(esp(m) + 0x48) == 0x482109),
            (0x48292c, 'temp_add_attempt', None),
        ]
        for address, name, predicate in more:
            self.coverage[name] = 0
            mu.hook_add(UC_HOOK_CODE, self._probe, begin=address, end=address, user_data=(name, predicate))

    # ---- hooks ----
    def _allocate(self, mu, address, size, data):
        count = self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        if self.heap + count > HG_HEAP + HG_HEAP_SIZE:
            raise MemoryError('height grid heap exhausted')
        block = self.heap
        self.heap = (self.heap + count + 15) & ~15
        mu.reg_write(UC_X86_REG_EAX, block)

    def _probe(self, mu, address, size, data):
        name, predicate = data
        if predicate is None or predicate(mu):
            self.coverage[name] += 1

    def _minimap(self, mu, address, size, index):
        self.minimap_calls[index] += 1

    # ---- memory helpers ----
    def byte(self, address, value=None):
        if value is None:
            return self.mu.mem_read(address, 1)[0]
        self.mu.mem_write(address, bytes([value & 0xff]))

    def word(self, address, value=None):
        if value is None:
            return struct.unpack('<H', self.mu.mem_read(address, 2))[0]
        self.mu.mem_write(address, struct.pack('<H', value & 0xffff))

    def dword(self, address, value=None):
        if value is None:
            return self.native.read(address)
        self.native.write(address, value & 0xffffffff)

    def call(self, address, args):
        try:
            self.loader._call(address, [a & 0xffffffff for a in args], 0, 20000000)
            return None
        except (UcError, RuntimeError) as caught:
            return f'{type(caught).__name__}: {caught} at eip {self.mu.reg_read(UC_X86_REG_EIP):#x}'

    # ---- scene ----
    def setup(self, scene):
        width, height, sea = scene['width'], scene['height'], scene['sea_level']
        heights = scene['heights_bytes']
        count = width * height
        cells = bytearray(count * 13)
        cells[4::13] = heights
        self.mu.mem_write(CELLS, bytes(cells))
        self.dword(GAME + 0x14233, width)
        self.dword(GAME + 0x14237, height)
        self.dword(GAME + 0x14223, width * 16)
        self.dword(GAME + 0x14227, height * 16)
        self.dword(GAME + 0x14287, CELLS)
        self.byte(GAME + 0x1427f, sea)
        self.mu.mem_write(GAME + 0x1428f, bytes(32))
        self.heap = HG_HEAP
        sp = 0x13ff000 - 4
        self.native.write(sp, 0x100f000)
        self.mu.reg_write(UC_X86_REG_ESP, sp)
        self.mu.emu_start(0x482c20, 0x100f000)
        pointer, w2, h2, pad = struct.unpack('<IiiI', self.mu.mem_read(GAME + 0x1428f, 16))
        self.hg = dict(w2=w2, h2=h2, pad=pad, sha=h16(bytes(self.mu.mem_read(pointer, pad * 2))))
        self.w2, self.h2 = int(width / 2), int(height / 2)
        self.los_pad = (self.w2 * self.h2 + 7) & ~7
        self.mapped_bytes = (width * height * 2) >> 2
        self.mu.mem_write(MAPPED, bytes(scene['initial_mapped']))
        self.dword(GAME + 0x14273, MAPPED)
        # player records
        self.players = scene['players']
        for slot in range(PLAYER_SLOTS):
            self.mu.mem_write(REC_BASE + slot * REC_SIZE, bytes(REC_SIZE))
        for p in self.players:
            rec = REC_BASE + p['slot'] * REC_SIZE
            self.dword(rec, 1)
            self.byte(rec + 0x73, p['type'])
            self.byte(rec + 0x146, p['index'])
            grid = LOS_BASE + p['slot'] * 0x20000
            self.mu.mem_write(grid, bytes(self.los_pad))
            self.dword(rec + 0x7c, grid)
            self.dword(rec + 0x80, self.w2)
            self.dword(rec + 0x84, self.h2)
            self.dword(rec + 0x88, self.los_pad)
        self.dword(GAME + 0x1485b, VIS)
        self.byte(GAME + 0x2a43, scene['local'])
        self.word(GAME + 0x14281, scene['flags'])
        self.byte(GAME + 0x142f1, 0)
        self.dword(GAME + TICK, scene['tick'])
        self.mu.mem_write(TEMP, bytes(TEMP_CAPACITY * TEMP_SIZE))
        self.dword(GAME + 0x1427b, TEMP)
        self.dword(GAME + 0x14277, 0)
        self.unit_count = scene['unit_slots']
        self.mu.mem_write(UNITS, bytes(UNIT_SIZE * (self.unit_count + 1)))
        self.mu.mem_write(DEFS, bytes(0x300 * (self.unit_count + 1)))
        self.dword(GAME + 0x14357, UNITS)
        self.dword(GAME + 0x1435b, UNITS + self.unit_count * UNIT_SIZE)
        self.minimap_calls = [0, 0]

    grid_stats = dict(bytes_ff=0, bytes_nonzero_not_one=0, steps_true=0, steps_circular=0, steps_los_on=0, steps_permanent=0,
                      steps_mapping_on=0, steps_mapping_off=0)

    def unit(self, index):
        return UNITS + index * UNIT_SIZE

    # ---- operations ----
    def apply(self, op):
        game = GAME
        if op.get('overlay'):
            self.word(game + 0x14281, self.word(game + 0x14281) | 8)
        self.byte(game + 0x142f1, 0)
        kind = op['op']
        if kind == 'create':
            u = self.unit(op['u'])
            d = DEFS + op['u'] * 0x300
            self.mu.mem_write(u, bytes(UNIT_SIZE))
            self.dword(u + 0x92, d)
            self.dword(u + 0x96, REC_BASE + op['owner'] * REC_SIZE)
            for i, value in enumerate(op['pos']):
                self.dword(u + 0x6a + 4 * i, value)
            self.word(u + 0x7a, op['origin'][0])
            self.word(u + 0x7c, op['origin'][1])
            self.byte(u + 0xf8, op['slot'])
            self.word(u + 0xa6, 1)
            self.dword(u + 0x110, op['unit_flags'])
            self.word(d + 0x202, op['sight'])
            self.word(d + 0x170, op['eye'])
            return self.call(0x482ac0, [u])
        if kind == 'move':
            u = self.unit(op['u'])
            for i, value in enumerate(op['pos']):
                self.dword(u + 0x6a + 4 * i, value)
            return self.call(0x4827b0, [u])
        if kind == 'death':
            u = self.unit(op['u'])
            d = self.dword(u + 0x92)
            rec = self.dword(u + 0x96)
            fault = None
            if self.dword(u + 0x110) & 0x10000000 and self.byte(rec + 0x146) == self.byte(game + 0x2a43):
                fault = self.call(0x482910, [u + 0x6a, s16(self.word(d + 0x202)), s16(self.word(d + 0x170)), 60])
            if fault is None and self.word(game + 0x14281) & 2:
                fault = self.call(0x482090, [u])
            self.word(u + 0xa6, 0)
            return fault
        if kind == 'temp':
            self.mu.mem_write(TEMP + 0xff0 - 12, b''.join(struct.pack('<I', v & 0xffffffff) for v in op['pos']))
            return self.call(0x482910, [TEMP + 0xff0 - 12, op['sight'], op['eye'], op['duration']])
        if kind == 'tick':
            self.dword(game + TICK, self.dword(game + TICK) + op['n'])
            return self.call(0x482130, [])
        if kind == 'rebuild':
            return self.call(0x4816a0, [op['reset']])
        if kind == 'flags':
            self.word(game + 0x14281, op['value'])
            return None
        raise ValueError(kind)

    def state(self):
        game = GAME
        los = []
        for p in self.players:
            grid = bytes(self.mu.mem_read(LOS_BASE + p['slot'] * 0x20000, self.los_pad))
            los.append(h16(grid))
            self.grid_stats['bytes_ff'] += grid.count(255)
            self.grid_stats['bytes_nonzero_not_one'] += len(grid) - grid.count(0) - grid.count(1)
        flags_now = self.word(game + 0x14281)
        self.grid_stats['steps_true' if flags_now & 4 else 'steps_circular'] += 1
        self.grid_stats['steps_los_on' if flags_now & 2 else 'steps_permanent'] += 1
        self.grid_stats['steps_mapping_on' if flags_now & 1 else 'steps_mapping_off'] += 1
        units = []
        for i in range(1, self.unit_count + 1):
            u = self.unit(i)
            units.append([s16(self.word(u + 0x7a)), s16(self.word(u + 0x7c)), self.byte(u + 0xf8)])
        entries = []
        for i in range(TEMP_CAPACITY):
            raw = bytes(self.mu.mem_read(TEMP + i * TEMP_SIZE, TEMP_SIZE))
            rec, _origin_ptr, sight, eye, slot_byte, _slot_ptr, x, y, z, expiry, col, row = struct.unpack('<IIhBBIiiiIhh', raw)
            owner = (rec - REC_BASE) // REC_SIZE if rec else -1
            # +0xb is the slot byte (0x482910 stores the slot pointer as entry+0xb)
            entries.append(f'{owner},{col},{row},{sight},{eye},{slot_byte},{x},{y},{z},{expiry}')
        return dict(los=los, mapped=h16(bytes(self.mu.mem_read(MAPPED, self.mapped_bytes))), units=units,
                    temp_count=s32(self.dword(game + 0x14277)), temp=h16(';'.join(entries).encode()),
                    flags=self.word(game + 0x14281), dirty=self.byte(game + 0x142f1), minimap=list(self.minimap_calls))

    def temp_detail(self):
        rows = []
        for i in range(TEMP_CAPACITY):
            raw = bytes(self.mu.mem_read(TEMP + i * TEMP_SIZE, TEMP_SIZE))
            rows.append(list(struct.unpack('<IIhBBIiiiIhh', raw)))
        return rows


# ---------------- scenario generation ----------------
MAP_KEYS = ['greenhaven', 'hundred-isles', 'lava-run', 'the-pass', 'biggie-biggs']
SIGHTS = [0, 10, 31, 32, 33, 63, 64, 96, 128, 150, 180, 200, 256, 287, 288, 300, 350, 400, 447, 448, 480, 600, 1000, 32767,
          -1, -32, -33, -1000, -32768]
EYES = [0, 1, 2, 3, 4, 5, 6, 10, 20, 40, 80, 128, 200, 254, 255, 256 + 7, 0x7f00 | 3]


def load_map(key):
    folder = Path('local/maps') / key
    scene = json.loads((folder / 'scene.json').read_text(encoding='utf-8'))
    return scene, (folder / 'heights.bin').read_bytes()


def make_scene(rng, index, maps):
    key = MAP_KEYS[index % len(MAP_KEYS)]
    info, heights = maps[key]
    full_w, full_h = info['height_grid_width'], info['height_grid_height']
    full = index % 25 == 0 and full_w <= 512
    if full:
        x0, y0, width, height = 0, 0, full_w, full_h
    else:
        width = rng.choice([2, 3, 5, 16, 17, 31, 32, 33, 48, 63, 64, 80, 97])
        height = rng.choice([2, 3, 4, 16, 17, 32, 33, 47, 64, 75, 96])
        width, height = min(width, full_w), min(height, full_h)
        x0, y0 = rng.randrange(full_w - width + 1), rng.randrange(full_h - height + 1)
    crop = bytes(heights[(y0 + r) * full_w + x0 + c] for r in range(height) for c in range(width))
    sea = rng.choice([info['sea_level'], info['sea_level'], 0, 0, 1, 2, 3, 100, 254, 255])
    mapped_size = (width * height * 2) >> 2
    fill = rng.choice(['zero', 'ones', 'random'])
    if fill == 'zero':
        initial = bytes(mapped_size)
    elif fill == 'ones':
        initial = b'\xff' * mapped_size
    else:
        initial = bytes(rng.randrange(256) for _ in range(mapped_size))
    players = [dict(slot=0, index=0, type=1), dict(slot=1, index=1, type=2), dict(slot=2, index=2, type=3),
               dict(slot=3, index=3, type=rng.choice([0, 4, 1]))]
    flags = rng.choice([0, 1, 2, 3, 4, 5, 6, 7]) | rng.choice([0, 8]) | rng.choice([0, 0, 0, 0x100])
    tick = rng.choice([0, 1000, rng.randrange(1 << 31), 0xffffffff - rng.randrange(200)])
    return dict(map=key, crop=[x0, y0, width, height], width=width, height=height, sea_level=sea, heights_bytes=crop,
                initial_mapped=initial, initial_mapped_kind=fill, players=players, local=rng.choice([0, 0, 1, 2]),
                flags=flags, tick=tick, unit_slots=rng.choice([3, 5, 6, 8]))


def random_pos(rng, scene):
    pw, ph = scene['width'] * 16, scene['height'] * 16
    roll = rng.random()
    if roll < 0.1:
        x, z = rng.randrange(-8, 48), rng.randrange(-8, 48)
    elif roll < 0.2:
        x, z = rng.choice([rng.randrange(-80, 20), rng.randrange(pw - 40, pw + 80)]), rng.choice([rng.randrange(-80, 40), rng.randrange(ph - 40, ph + 120)])
    elif roll < 0.23:
        return [rng.randrange(-(1 << 31), 1 << 31) for _ in range(3)]
    else:
        x, z = rng.randrange(-40, pw + 40), rng.randrange(-40, ph + 60)
    sea = scene['sea_level']
    y = rng.choice([rng.randrange(0, sea + 3), sea + 1, sea, rng.randrange(0, 256), rng.randrange(256, 700),
                    rng.randrange(-200, 0), rng.randrange(0, 12), rng.randrange(32000, 40000)])
    return [x * 65536 + rng.randrange(65536), y * 65536 + rng.randrange(65536), z * 65536 + rng.randrange(65536)]


def nudge(rng, pos):
    x, y, z = pos
    roll = rng.random()
    if roll < 0.3:
        return [s32(x + rng.randrange(-3 << 16, 3 << 16)), s32(y + rng.randrange(-2 << 16, 2 << 16)), s32(z + rng.randrange(-3 << 16, 3 << 16))]
    if roll < 0.7:
        return [s32(x + rng.randrange(-40 << 16, 40 << 16)), s32(y + rng.randrange(-8 << 16, 8 << 16)), s32(z + rng.randrange(-40 << 16, 40 << 16))]
    return [s32(x + rng.randrange(-200 << 16, 200 << 16)), s32(y + rng.randrange(-60 << 16, 60 << 16)), s32(z + rng.randrange(-200 << 16, 200 << 16))]


def generate_ops(rng, scene, steps, family):
    alive = {}
    temp_positions = []
    temp_family = family in ('temp', 'temp_spot')
    spot = None
    if family == 'temp_spot':
        spot = [rng.randrange(0, min(scene['width'], 8) * 16) << 16, rng.randrange(-4 << 16, 2 << 16),
                rng.randrange(0, min(scene['height'], 8) * 16) << 16]
    # temp_spot also floods the 20-entry temp array (0x482910 capacity test) and, in half of its sequences, keeps ticks
    # short so the entries survive long enough to reach the cap.
    flood = family == 'temp_spot'
    short_ticks = flood and rng.random() < 0.5
    ops = [dict(op='rebuild', reset=rng.choice([1, 1, 1, 0]))]
    for _ in range(steps * 2 if flood else steps):
        dead = [i for i in range(1, scene['unit_slots'] + 1) if i not in alive]
        roll = rng.random()
        overlay = rng.random() < 0.5
        if flood and rng.random() < 0.45:
            pos, eye = (spot, rng.choice([0, 1, 2, 3])) if rng.random() < 0.7 else (random_pos(rng, scene), rng.choice(EYES))
            op = dict(op='temp', pos=pos, sight=rng.choice(SIGHTS), eye=eye, duration=60)
        elif short_ticks and roll > 0.83 and roll < 0.9:
            op = dict(op='tick', n=rng.choice([0, 1, 1, 5, 10]))
        elif dead and (roll < 0.12 or not alive):
            u = rng.choice(dead)
            pos = random_pos(rng, scene)
            stale = rng.random() < 0.15
            op = dict(op='create', u=u, owner=rng.choice([0, 1, 2, 3, 0]), pos=pos,
                      origin=[rng.choice([0, rng.randrange(-40, 80)]), rng.choice([0, rng.randrange(-40, 80)])] if stale else [0, 0],
                      slot=rng.randrange(256) if stale and rng.random() < 0.5 else 0,
                      sight=rng.choice(SIGHTS) if rng.random() < 0.8 else rng.randrange(-100, 700),
                      eye=rng.choice(EYES), unit_flags=rng.choice([0x10000000, 0x10000000, 0x10000003, 0]))
            alive[u] = pos
        elif alive and roll < 0.62:
            u = rng.choice(sorted(alive))
            pos = nudge(rng, alive[u]) if rng.random() < 0.85 else random_pos(rng, scene)
            alive[u] = pos
            op = dict(op='move', u=u, pos=pos)
        elif alive and roll < (0.72 if temp_family else 0.68):
            u = rng.choice(sorted(alive))
            del alive[u]
            op = dict(op='death', u=u)
        elif roll < (0.82 if temp_family else 0.71):
            # Reusing an earlier temp position with a low eye exercises the stale entry origin (+0x20) early-out.
            if spot is not None and rng.random() < 0.85:
                # temp_spot: one fixed low position, so a reused backing slot's stale origin equals the new centre.
                pos, eye = spot, rng.choice([0, 1, 2, 3])
            elif temp_positions and rng.random() < 0.4:
                pos, eye = rng.choice(temp_positions), rng.choice([0, 1, 2, 3])
            else:
                pos, eye = random_pos(rng, scene), rng.choice(EYES)
                if rng.random() < 0.3:
                    pos = [rng.randrange(0, 40 << 16), rng.randrange(-4 << 16, 2 << 16), rng.randrange(0, 40 << 16)]
            temp_positions.append(pos)
            op = dict(op='temp', pos=pos, sight=rng.choice(SIGHTS), eye=eye, duration=60)
        elif roll < (0.9 if temp_family else 0.83):
            op = dict(op='tick', n=rng.choice([0, 1, 1, 5, 30, 59, 60, 61, 100] + ([10, 20, 25, 30, 40] if temp_family else [])))
        elif roll < (0.93 if temp_family else 0.88):
            op = dict(op='rebuild', reset=rng.choice([0, 1]))
        elif roll < 0.96:
            flags_bit = rng.choice([1, 2, 4, 4])
            ops.append(dict(op='flags', value=None, toggle=flags_bit, overlay=overlay))
            op = dict(op='rebuild', reset=1 if flags_bit == 1 else 0) if rng.random() < 0.6 else dict(op='tick', n=rng.choice([0, 1, 61]))
        else:
            op = dict(op='flags', value=rng.randrange(16) | rng.choice([0, 0, 0x2000]))
        op['overlay'] = overlay
        ops.append(op)
    return ops


def run_sequence(oracle, scene, ops):
    oracle.setup(scene)
    records = []
    fault = None
    for step, op in enumerate(ops):
        if op['op'] == 'flags' and op.get('value') is None:
            op['value'] = oracle.word(GAME + 0x14281) ^ op.pop('toggle')
        fault = oracle.apply(op)
        if fault is not None:
            records.append(dict(fault=fault))
            ops[:] = ops[:step + 1]
            break
        records.append(oracle.state())
    return records, fault


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=Path('local/original/TotalA.exe'))
    parser.add_argument('--cob', type=Path, default=Path('local/viewer-assets/armcom.cob'))
    parser.add_argument('--sequences', type=int, default=600)
    parser.add_argument('--steps', type=int, default=45)
    parser.add_argument('--seed', type=int, default=0x482270)
    parser.add_argument('--output', type=Path, default=Path('local/visibility/native-los-stamp.json'))
    parser.add_argument('--only', type=int, default=None)
    args = parser.parse_args()
    tdf = Path('local/visibility/los.tdf').read_bytes()
    vismasks = json.loads(Path('local/visibility/vismasks.json').read_text(encoding='utf-8'))
    oracle = StampOracle(args.exe.read_bytes(), args.cob.read_bytes(), tdf, vismasks)
    maps = {key: load_map(key) for key in MAP_KEYS}
    sequences = []
    totals = dict(steps=0, faults=0, ops={})
    for index in range(args.sequences):
        rng = random.Random(args.seed * 1000003 + index)
        family = ['mixed', 'mixed', 'temp', 'mixed', 'mixed', 'temp_spot'][index % 6]
        scene = make_scene(rng, index, maps)
        if family == 'temp_spot':
            # mostly True LOS with LOS on, and a sea level low enough for eye heights <= 5
            if rng.random() < 0.75:
                scene['flags'] |= 6
            scene['sea_level'] = rng.choice([0, 0, 1, 2, scene['sea_level']])
        ops = generate_ops(rng, scene, args.steps, family)
        if args.only is not None and index != args.only:
            continue
        records, fault = run_sequence(oracle, scene, ops)
        totals['steps'] += len(records)
        totals['faults'] += fault is not None
        for op in ops:
            totals['ops'][op['op']] = totals['ops'].get(op['op'], 0) + 1
        public = {k: v for k, v in scene.items() if k not in ('heights_bytes', 'initial_mapped')}
        if scene['initial_mapped_kind'] == 'random':
            public['initial_mapped'] = base64.b64encode(scene['initial_mapped']).decode()
        public['height_grid'] = oracle.hg
        sequences.append(dict(index=index, family=family, scene=public, ops=ops, states=records, fault=fault))
        if fault:
            print(f'NATIVE_LOS_STAMP seq {index}: fault at step {len(records) - 1} ({ops[-1]["op"]}): {fault}', flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(
        version=1, exe_sha256=EXE_HASH, frame_count=oracle.frame_count, table_count=len(oracle.tables),
        tables_sha=h16('#'.join('|'.join(' '.join(f'{x},{y}' for x, y in ray) for ray in table) for table in oracle.tables).encode()),
        table_minus_one='16 zero bytes written before the table vector at %#x' % (oracle.table_begin - 16),
        stubs={'0x4b4f10': 'operator new wrapper (height-grid build only): bump allocator',
               '0x4b4f20': 'operator delete wrapper: no-op',
               '0x466c20': 'minimap terrain redraw (end of 0x4816a0): ret + call count; would consume dirty bit 4',
               '0x466dc0': 'minimap unit dots (end of 0x4816a0): ret + call count'},
        assumptions=['16 zero bytes before the ray table vector (table index -1 = empty ray vector)',
                     'temp LOS array starts zeroed; entry origin +0x20 is left stale by 0x482910',
                     'unit +0xa6 cleared by the harness after death'],
        totals=totals, coverage=oracle.coverage, grid_stats=oracle.grid_stats, sequences=sequences)), encoding='utf-8')
    print('NATIVE_LOS_STAMP coverage', oracle.coverage)
    print('NATIVE_LOS_STAMP grid stats', oracle.grid_stats)
    print(f'NATIVE_LOS_STAMP {len(sequences)} sequences, {totals["steps"]} steps, {totals["faults"]} faulted; ops {totals["ops"]}')


if __name__ == '__main__':
    main()
