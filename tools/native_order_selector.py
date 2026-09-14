"""Original order/cursor selector and group issue oracle (TotalA.exe 0x43f0e0, 0x43e490, 0x48d220, 0x48cf30).

Runs the ORIGINAL x86 in Unicorn (no game startup) over randomized synthetic scenes and writes:
  local/orders/native-order-selector.json          every case: scene, calls and native results / queue dumps
  analysis/native-order-selector-validation.json   summary, stubs, coverage, scope

Unmodified native code exercised:
  0x43f0e0 order selector (both jump tables' targets, recursion, inline featureVisible), 0x43e490 cursor selector,
  0x4899b0 canRepair, 0x489960 canReclaimUnit, 0x489a90 canLoad, 0x4815a0 cell lookup, 0x438760 order name lookup
  (binary search + 0x4f8a70), 0x438830 type entry, 0x43e470 hover-exclusion mode test, 0x48d220 cursor aggregation
  (0x40c9f0/0x48ddc0/0x480100/0x406c00 vector helpers), 0x48cf30 group issue (0x4e43a0 ftol, 0x4e4400 _allmul,
  0x4e43d0 _allshr), 0x43afc0 issue / shift toggle, 0x43adc0 insert, 0x43a0c0 constructor, 0x4895c0 target link,
  0x43a1f0 destroy (goal block with a null goal), 0x438880 acknowledgement, 0x47f780 unit reply gate, 0x4c5740 sound
  lookup (sound table pointer 0x51fdb8 is null in the image, so it returns its argument), the order table build
  0x403180/0x406bf0/0x415b20 -> 0x43bc90 (reused from tools/native_order_queue.py).

Stubs (every replaced boundary):
  0x49abb0 unit range test (stdcall ret 0xc) and 0x49aa80 position range test (stdcall ret 0x10): return a recorded
      per-unit answer, call recorded (unit, target or position, slot).
  0x47fad0 unit reply queue (thiscall ret 0xc, sound priority queue): recorded (unit, reply index, sound), not executed.
  0x4b4f10 / 0x4b4f20 operator new / delete: bump allocator; 0x56-byte allocations get sequential order ids.
  0x489800 clear weapon targets and 0x48a0f0 aim reset: recorded only (from native_order_queue.Native).
  Order handlers are redirected to the queue oracle's scripted stub but are never called here.
NaN float fields are carried through JSON as the string 'NaN' (edge phase). Branch-edge coverage of the unmodified
routines is measured with code hooks and written to the summary (edges no input can take are listed with reasons).
Not emulated: 0x4815a0(null) crashes (null pos that reaches it is not generated), back-link / feature indices outside
  the synthetic grid and feature table, hover ids outside the unit array, +0x146 indices >= 10 (not generated).
Usage: python tools/native_order_selector.py [select group edge_select edge_group]   (defaults 12000 2500 4000 500)
"""
import json
from pathlib import Path
import random
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'local/python-deps'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from unicorn import UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ECX, UC_X86_REG_EIP, UC_X86_REG_ESP
import native_order_queue as noq

EXE_HASH = noq.EXE_HASH
GAME = noq.GAME
G_TICK = 0x38a47
SCENE = 0x2100000
SCENE_SIZE = 0x80000
UNITS = SCENE                      # [G+0x14357] unit array, id * 0x118
MAX_UNITS = 32
DEFS = SCENE + 0x4000              # one definition per unit id, 0x250 each
WEAPONS = SCENE + 0xa000           # 3 weapon records per unit id, 0x130 each
RES = SCENE + 0x14000              # resource record per unit id, 0x100 each
MOVE_OBJ = SCENE + 0x17000         # locomotion object: [obj] -> vt, [vt+4] == 0 (destroy goal block sees no goal)
GRID = SCENE + 0x18000             # feature cells, 13 bytes each
BITMAP = SCENE + 0x20000           # seen bitmap words
FEATURES = SCENE + 0x28000         # feature definitions, 0x100 each (+0xfe flags)
STRINGS = SCENE + 0x30000
SCRATCH = SCENE + 0x40000          # non-order allocations (0x48d220 vectors)
CUSTOM_SOUND = STRINGS
CUSTOM_SOUND_NAME = 'custom-reply'
OUT = noq.WORK + 0x9000
INPUT = noq.WORK + 0x9100
POS_ARG = noq.WORK + 0x9200
PLAYER_BASE = GAME + 0x1b63
PLAYER_SIZE = 0x14b
PLAYERS = 10
FEATURE_SLOTS = 16
SEEN_WORDS = 0x400                 # native bitmap size (words past the JSON list stay zero)
SEEN_JSON_WORDS = 0x100
U = 0x118
MASK = 0xffffffff

F245 = dict(STANDMOVE=1, STANDFIRE=2, ONOFF=4, STOP=8, ATK=0x10, GUARD=0x20, PATROL=0x40, MOVE=0x80, LOAD=0x100,
            REP=0x200, RECL=0x400, RES=0x800, CAPT=0x1000, DGUN=0x4000, NOTRANSPORT=0x80000)
F241 = dict(BUILDER=0x40, AIRBASE=0x200, FLY=0x800, HOVER=0x1000, TELEPORT=0x2000, FLOATER=0x80000, UPRIGHT=0x100000,
            AMPHIB=0x200000, HOVERATTACK=0x8000000, KAMIKAZE=0x10000000)
B = lambda *names: sum(F245[n] for n in names)
C = lambda *names: sum(F241[n] for n in names)
CLASSES = {
    'ground_combat': dict(loco=1, armed=1, f245=B('MOVE', 'ATK', 'GUARD', 'PATROL', 'STOP', 'STANDMOVE', 'STANDFIRE')),
    'static_defense': dict(loco=0, armed=1, f110=0x20000000, f245=B('ATK', 'STOP', 'STANDFIRE')),
    'factory': dict(loco=0, f245=B('MOVE', 'PATROL', 'GUARD', 'STOP', 'STANDMOVE'), f241=C('BUILDER'), build=1),
    'fighter': dict(loco=1, armed=1, f241=C('FLY'), f245=B('MOVE', 'ATK', 'GUARD', 'PATROL', 'STANDMOVE', 'STANDFIRE')),
    'bomber': dict(loco=1, armed=1, f241=C('FLY'), w1=0x100, f245=B('MOVE', 'ATK', 'GUARD', 'PATROL')),
    'gunship': dict(loco=1, armed=1, f241=C('FLY', 'HOVERATTACK'), f245=B('MOVE', 'ATK', 'PATROL')),
    'mobile_builder': dict(loco=1, f241=C('BUILDER'), build=1, f245=B('MOVE', 'GUARD', 'PATROL', 'RECL', 'REP', 'STOP', 'STANDMOVE')),
    'air_builder': dict(loco=1, f241=C('BUILDER', 'FLY'), build=1, f245=B('MOVE', 'GUARD', 'PATROL', 'RECL', 'REP')),
    'commander': dict(loco=1, armed=1, build=1, f241=C('BUILDER', 'AMPHIB'),
                      f245=B('MOVE', 'ATK', 'GUARD', 'PATROL', 'RECL', 'REP', 'CAPT', 'DGUN', 'STOP', 'STANDMOVE', 'STANDFIRE')),
    'resurrector': dict(loco=1, f245=B('MOVE', 'RECL', 'REP', 'RES', 'PATROL')),
    'ground_transport': dict(loco=1, f245=B('MOVE', 'LOAD', 'GUARD', 'PATROL'), cap=1),
    'air_transport': dict(loco=1, f241=C('FLY'), f245=B('MOVE', 'LOAD', 'GUARD', 'PATROL'), cap=1),
    'hovercraft': dict(loco=1, armed=1, f241=C('HOVER'), f245=B('MOVE', 'ATK', 'PATROL')),
    'kamikaze': dict(loco=1, f241=C('KAMIKAZE'), f245=B('MOVE', 'ATK')),
    'airbase': dict(loco=0, f241=C('AIRBASE'), f245=B('STOP')),
    'teleporter': dict(loco=0, f241=C('TELEPORT'), f245=B('STOP')),
    'random': dict(),
}
MODE_CLASSES = {3: ['ground_combat', 'static_defense', 'fighter', 'bomber', 'gunship', 'hovercraft', 'kamikaze', 'commander'],
                4: ['commander'], 5: ['air_transport', 'ground_transport'], 6: ['air_transport', 'ground_transport'],
                7: ['ground_combat', 'fighter', 'mobile_builder'], 8: ['mobile_builder', 'air_builder', 'commander'],
                9: ['mobile_builder', 'factory', 'fighter', 'ground_combat'], 12: ['mobile_builder', 'air_builder', 'resurrector'],
                13: ['commander'], 14: ['mobile_builder', 'air_builder', 'factory']}
MODES = list(range(0, 16)) + list(range(1, 15)) * 4 + [1, 2, 3, 8, 12] * 3 + [0x101, 0x203, 0xff]


EDGE_RANGES = {
    '0x43e490': (0x43e490, 0x43f0a5), '0x43f0e0': (0x43f0e0, 0x4401ea), '0x489960': (0x489960, 0x4899a1),
    '0x4899b0': (0x4899b0, 0x489a6a), '0x489a90': (0x489a90, 0x489ba1), '0x48cf30': (0x48cf30, 0x48d216),
    '0x48d220': (0x48d220, 0x48d411), '0x43e470': (0x43e470, 0x43e48b), '0x438880': (0x438880, 0x4388a1),
    '0x47f780': (0x47f780, 0x47f7dd),
}
# Conditional edges no input can take (checked by reading the listing).
UNREACHABLE_EDGES = {
    (0x43ea64, 'taken'): 'ally (esi) re-test; 0x43ea34 already passed',
    (0x43edf4, 'taken'): 'hover (edi) re-test; 0x43edb8 already passed',
    (0x43f23e, 'fall'): 'reached only from 0x43f219 fall-through, i.e. depth < sea',
    (0x43f329, 'taken'): '0x43f31b with a non-air target is reached only through 0x43f300 (hoverattack set)',
    (0x43f592, 'taken'): 'pos was already dereferenced by 0x4815a0',
    (0x43f61d, 'taken'): 'pos was already dereferenced by 0x4815a0',
    (0x43f91a, 'taken'): 'ally (ebx) re-test; 0x43f8db already passed',
    (0x43faae, 'taken'): 'ally (ebx) re-test; 0x43fa4f already passed',
    (0x43fee2, 'taken'): 'hover (edi) re-test; 0x43fe93 already passed',
    (0x48d064, 'taken'): 'n > 0 implies first <= last',
    (0x48d3c8, 'taken'): 'a non-empty vector has begin != end',
}


def s32(v):
    v &= MASK
    return v - 0x100000000 if v & 0x80000000 else v


def rbits(rng, bits, p):
    return sum(b for b in bits if rng.random() < p)


# ----------------------------------------------------------------------------------------------- scene generation
class SceneGen:
    def __init__(self, rng):
        self.rng = rng

    def float_value(self, choices):
        return self.rng.choice(choices)

    def definition(self, cls):
        rng = self.rng
        t = CLASSES[cls]
        f245 = t.get('f245', rbits(rng, list(F245.values()), 0.35))
        f241 = t.get('f241', rbits(rng, list(F241.values()), 0.2) if cls == 'random' else 0)
        if rng.random() < 0.35:
            for _ in range(rng.randint(1, 3)):
                f245 ^= rng.choice(list(F245.values()))
        if rng.random() < 0.25:
            f241 ^= rng.choice(list(F241.values()))
        if rng.random() < 0.05:
            f245 |= rng.choice([0x10000000, 0x80000000, 0x2000, 0x8000])
        maxdamage = rng.choice([100, 500, 3000, 0xffff, 0x8000, rng.randint(1, 5000)])
        return dict(
            f241=f241 & MASK, f245=f245 & MASK,
            footprintx_14a=rng.choice([1, 2, 3, 4, 6, 8, 0xfffe, 0x8001]),
            buildlist_156=rng.choice([0, 0x4fd000]) if t.get('build') is None else rng.choice([0x4fd000, 0x4fd000, 0]),
            maxy_16e=s32((rng.choice([0, 10, 20, 40, -5, -30, 0x7fff]) << 16) + rng.choice([0, 0x8000, rng.randrange(0x10000)])),
            depth_1be=rng.choice([0, 10, 30, 50, -20, 0x7fff, -0x8000]),
            minwaterdepth_1c0=rng.choice([-10000, -1, 0, 10, 255]),
            weapon1_1ee=dict(flags_111=t.get('w1', 0) | rbits(rng, [0x100, 0x10000, 0x20000, 2], 0.2)),
            maxdamage_1fa=maxdamage if rng.random() < 0.95 else rng.choice([MASK, 0x80000000]),
            transport_size_22a=rng.choice([0, 1, 2, 3, 4, 8, 255]) if t.get('cap') else rng.choice([0, 0, 2]),
            transport_capacity_22b=rng.choice([0, 1, 2, 3, 5]) if t.get('cap') else rng.choice([0, 0, 1]),
        )

    def weapon(self):
        rng = self.rng
        return dict(flags_111=rbits(rng, [2, 0x100, 0x10000, 0x20000, 0x4000000], 0.25),
                    energy_c0=rng.choice([0.0, 100.0, 500.0, 1200.5]), metal_c4=rng.choice([0.0, 0.0, 50.0, 300.25]))

    def unit(self, uid, player, owner, cls=None):
        rng = self.rng
        cls = cls or rng.choice(list(CLASSES))
        t = CLASSES[cls]
        d = self.definition(cls)
        f110 = rng.randrange(4) if rng.random() < 0.3 else rng.choice([0, 0, 0, 1, 2])
        f110 |= t.get('f110', 0)
        if t.get('armed') and rng.random() < 0.9:
            f110 |= 0x80000000
        elif rng.random() < 0.15:
            f110 |= 0x80000000
        f110 |= rbits(rng, [0x10, 0x20, 0x4000, 0x20000000, 0x40000000, 0x1000], 0.3)
        if rng.random() < 0.88:
            f110 |= 0x10000000
        health = rng.choice([d['maxdamage_1fa'] & 0xffff, d['maxdamage_1fa'] & 0xffff, 50, 0, 0x8000, 0xffff, rng.randrange(0x10000)])
        loco = t.get('loco', rng.randrange(2))
        if rng.random() < 0.08:
            loco ^= 1
        return dict(
            id=uid, cls=cls, loco_0=loco, weapons=[self.weapon(), self.weapon(), self.weapon()],
            slot1_3b=rbits(rng, [2, 0x10, 1], 0.4),
            x_6a=s32(rng.randint(-0x100000, 0x1000000) + rng.randrange(0x10000)),
            y_6e=s32((rng.choice([0, 5, 20, 40, -10, -40, 80, rng.randint(-60, 100)]) << 16) + rng.choice([0, rng.randrange(0x10000)])),
            z_72=s32(rng.randint(-0x100000, 0x1000000) + rng.randrange(0x10000)),
            transporter_86=0, cargo_8a=[], def_92=d, player_96=player,
            alive_a6=0 if rng.random() < 0.08 else rng.randint(1, 0xffff),
            resources_ec=dict(energy_8c=rng.choice([0.0, 50.0, 100.0, 499.5, 2000.0]), metal_98=rng.choice([0.0, 25.0, 50.0, 300.25, 900.0])),
            select_fb=rng.choice([0, 0, 0, 0, 5, 0x100]), owner_ff=owner,
            build_104=rng.choice([0.0, 0.0, 0.0, -0.0, 0.5, 1.0, 1e-7, 0.999]),
            health_108=health, f110=f110 & MASK,
        )

    def players(self, count, local):
        rng = self.rng
        players = []
        for i in range(count):
            alliance = [rng.choice([0, 0, 1, 0xff]) for _ in range(PLAYERS)]
            if rng.random() < 0.8:
                alliance[i] = 1
            index = i if rng.random() < 0.93 else rng.randrange(count)
            players.append(dict(index_146=index, seen_w_80=rng.choice([4, 8, 8, 16, 1, 0, 0x80000000]),
                                seen_h_84=rng.choice([4, 8, 8, 16, 1, 0]), alliance_108=alliance,
                                units_first_67=0, units_last_6b=0))
        return players

    def game(self, units, players):
        rng = self.rng
        w, h = rng.choice([4, 8, 12, 16]), rng.choice([4, 8, 12, 16])
        count = rng.choice([0, 2, 4, 8, 12, 16])
        cells = []
        for i in range(w * h):
            r = rng.random()
            if r < 0.4:
                cells.append([0xffff, 0, 0])
            elif r < 0.75:
                cells.append([rng.randrange(FEATURE_SLOTS), rng.randrange(3), rng.randrange(3)])
            elif r < 0.88:
                b10 = rng.randint(0, min(255, i // w))
                b11 = rng.randint(0, min(255, i - b10 * w))
                cells.append([0xfffe, b10, b11])
            else:
                cells.append([rng.choice([0xfffc, 0xfffd, 0xfffb, 0xffff]), rng.randrange(3), rng.randrange(3)])
        return dict(
            local_player_2a42=rng.choice([0, 0, 1, 2]), viewing_player_2a43=rng.choice([0, 0, 1, 2, 5, 17]),
            interface_37efa=rng.choice([0, 0, 1, 1, 2, 0x101]), sea_level_1427f=rng.choice([0, 0, 20, 40, 128, 255]),
            hover_2cba=0, cursor_2caa=[0, 0, 0], mode_2cc3=1,
            map_w_14233=w, map_h_14237=h, cells_14287=cells,
            feature_count_14253=count, feature_flags_1426f=[rng.choice([0, 0x80, 0x80, 0xff, 0x7f]) for _ in range(FEATURE_SLOTS)],
            seen_14273=[rng.choice([0, 0xffff, 1, 2, 4, 5, 0x8000, rng.randrange(0x10000)]) for _ in range(SEEN_JSON_WORDS)],
            players=players, units=units, tick=rng.randrange(0x100000),
        )

    def cursor(self, g):
        rng = self.rng
        r = rng.random()
        if r < 0.6:
            cx, cz = rng.randrange(g['map_w_14233']), rng.randrange(g['map_h_14237'])
            x = (cx * 16 + rng.randrange(16)) << 16
            z = (cz * 16 + rng.randrange(16)) << 16
        elif r < 0.9:
            x = rng.randint(-40, 16 * 17) << 16
            z = rng.randint(-40, 16 * 17) << 16
        else:
            x = rng.choice([0x7fff0000, -0x80000000, 0x10000, -0x10000, 0x7fffffff])
            z = rng.choice([0x7fff0000, -0x80000000, 0x10000, 0])
        y = (rng.choice([0, 0, 10, 60, 200, -20, rng.randint(-100, 300)]) << 16) + rng.choice([0, rng.randrange(0x10000)])
        return [s32(x + rng.randrange(0x10000)), s32(y), s32(z + rng.randrange(0x10000))]


# ----------------------------------------------------------------------------------------------- native harness
class Native(noq.Native):
    def __init__(self, executable):
        super().__init__(executable)
        mu = self.mu
        mu.mem_map(SCENE, SCENE_SIZE)
        self.scratch = SCRATCH
        for address, pop in ((0x49abb0, 0xc), (0x49aa80, 0x10), (0x47fad0, 0xc)):
            mu.mem_write(address, b'\xc2' + struct.pack('<H', pop))
        mu.hook_add(UC_HOOK_CODE, self.h_range_unit, begin=0x49abb0, end=0x49abb0)
        mu.hook_add(UC_HOOK_CODE, self.h_range_pos, begin=0x49aa80, end=0x49aa80)
        mu.hook_add(UC_HOOK_CODE, self.h_reply, begin=0x47fad0, end=0x47fad0)
        mu.hook_add(UC_HOOK_CODE, self.h_issue, begin=0x43afc0, end=0x43afc0)
        self.range_answers = {}
        self.g = None
        # branch-edge coverage of the unmodified routines (conditional jumps decoded with capstone)
        self.jcc = {}
        self.edges = set()
        self.reached = set()
        self.prev = None
        from capstone import Cs, CS_ARCH_X86, CS_MODE_32
        cs = Cs(CS_ARCH_X86, CS_MODE_32)
        for name, (lo, hi) in EDGE_RANGES.items():
            code = bytes(mu.mem_read(lo, hi - lo))
            for insn in cs.disasm(code, lo):
                if insn.mnemonic.startswith('j') and insn.mnemonic != 'jmp':
                    self.jcc[insn.address] = (name, insn.mnemonic, int(insn.op_str, 16), insn.address + insn.size)
            mu.hook_add(UC_HOOK_CODE, self.h_edge, begin=lo, end=hi - 1)

    def h_edge(self, mu, address, size, data):
        if self.prev in self.jcc:
            self.edges.add((self.prev, address))
        self.reached.add(address)
        self.prev = address

    def edge_report(self):
        per = {}
        uncovered = []
        reachable_gaps = 0
        for address, (name, mnemonic, target, fall) in sorted(self.jcc.items()):
            entry = per.setdefault(name, [0, 0])
            for dst, label in ((target, 'taken'), (fall, 'fall')):
                entry[1] += 1
                if (address, dst) in self.edges:
                    entry[0] += 1
                    continue
                reason = UNREACHABLE_EDGES.get((address, label))
                if reason is None:
                    reachable_gaps += 1
                    reason = 'NOT PROVEN UNREACHABLE' + ('' if address in self.reached else ' (jump never reached)')
                uncovered.append(f'{name} {address:#x} {mnemonic} {label} -> {dst:#x}: {reason}')
        return dict(covered=sum(v[0] for v in per.values()), total=sum(v[1] for v in per.values()),
                    uncovered_reachable=reachable_gaps, per_routine={k: f'{v[0]}/{v[1]}' for k, v in per.items()},
                    uncovered=uncovered)

    # allocation: orders keep the queue oracle's ids, anything else comes from a scratch bump heap
    def h_alloc(self, mu, address, size, data):
        count = self.arg(0)
        if self.table_mode or count == noq.ORDER_SIZE:
            return super().h_alloc(mu, address, size, data)
        base = self.scratch
        self.scratch += (count + 8) & ~3
        if self.scratch >= SCENE + SCENE_SIZE:
            raise RuntimeError('scratch heap exhausted')
        mu.reg_write(UC_X86_REG_EAX, base)

    def h_free(self, mu, address, size, data):
        if not self.table_mode and self.arg(0) in self.ids:
            self.events.append(['free', self.ids[self.arg(0)]])

    def unit_ref(self, address):
        if address == 0:
            return 0
        if UNITS <= address < UNITS + MAX_UNITS * U and (address - UNITS) % U == 0:
            return (address - UNITS) // U
        raise AssertionError(f'unexpected unit pointer {address:#x}')

    def h_range_unit(self, mu, address, size, data):
        uid, tid, slot = self.unit_ref(self.arg(0)), self.unit_ref(self.arg(1)), self.arg(2)
        self.events.append(['range_unit', uid, tid, slot])
        mu.reg_write(UC_X86_REG_EAX, self.range_answers.get(uid, [0, 0])[0])

    def h_range_pos(self, mu, address, size, data):
        uid, from_ptr, pos_ptr, slot = self.unit_ref(self.arg(0)), self.arg(1), self.arg(2), self.arg(3)
        if from_ptr != self.arg(0) + 0x6a:
            raise AssertionError('0x49aa80 origin is not the unit position')
        pos = list(struct.unpack('<iii', self.mu.mem_read(pos_ptr, 12)))
        self.events.append(['range_pos', uid, pos, slot])
        mu.reg_write(UC_X86_REG_EAX, self.range_answers.get(uid, [0, 0])[1])

    def h_issue(self, mu, address, size, data):
        # observer only: 0x43afc0(t, shift, unit, target, pos, p36, p3a) runs unmodified
        pos_ptr = self.arg(4)
        pos = list(struct.unpack('<iii', self.mu.mem_read(pos_ptr, 12))) if pos_ptr else None
        self.events.append(['issue', self.unit_ref(self.arg(2)), self.arg(0), self.arg(1), self.unit_ref(self.arg(3)), pos,
                            s32(self.arg(5)), s32(self.arg(6))])

    def h_reply(self, mu, address, size, data):
        uid, index, sound = self.unit_ref(self.arg(0)), self.arg(1), self.arg(2)
        name = CUSTOM_SOUND_NAME if sound == CUSTOM_SOUND else (self.cstr(sound) if 0x400000 <= sound < 0x600000 else f'{sound:#x}')
        self.events.append(['reply', uid, index, name])

    # ----- scene image -----
    def w8(self, a, v):
        self.mu.mem_write(a, bytes([v & 0xff]))

    def w16(self, a, v):
        self.mu.mem_write(a, struct.pack('<H', v & 0xffff))

    def wf(self, a, v):
        # 'NaN' (JSON-safe) is written as a quiet NaN
        self.mu.mem_write(a, struct.pack('<f', float('nan') if v == 'NaN' else v))

    def player_address(self, index):
        return PLAYER_BASE + index * PLAYER_SIZE

    def unit_address(self, uid):
        return 0 if uid == 0 else UNITS + uid * U

    def load(self, g):
        self.g = g
        mu = self.mu
        mu.mem_write(SCENE, bytes(0x40000))
        mu.mem_write(GAME + 0x2a00, bytes(0x400))
        mu.mem_write(PLAYER_BASE, bytes(PLAYER_SIZE * PLAYERS))
        mu.mem_write(GAME + 0x14200, bytes(0x200))
        self.heap = noq.HEAP
        self.scratch = SCRATCH
        self.ids = {}
        self.next_id = 1
        self.write(GAME + G_TICK, g['tick'])
        self.w8(GAME + 0x2a42, g['local_player_2a42'])
        self.w8(GAME + 0x2a43, g['viewing_player_2a43'])
        self.write(GAME + 0x37efa, g['interface_37efa'])
        self.w8(GAME + 0x1427f, g['sea_level_1427f'])
        self.write(GAME + 0x14357, UNITS)
        self.write(GAME + 0x14233, g['map_w_14233'])
        self.write(GAME + 0x14237, g['map_h_14237'])
        self.write(GAME + 0x14287, GRID)
        for i, (occ, b10, b11) in enumerate(g['cells_14287']):
            self.w16(GRID + i * 13 + 8, occ)
            self.w8(GRID + i * 13 + 10, b10)
            self.w8(GRID + i * 13 + 11, b11)
        self.write(GAME + 0x14253, g['feature_count_14253'])
        self.write(GAME + 0x1426f, FEATURES)
        for i, flags in enumerate(g['feature_flags_1426f']):
            self.w8(FEATURES + i * 0x100 + 0xfe, flags)
        self.write(GAME + 0x14273, BITMAP)
        mu.mem_write(BITMAP, struct.pack(f'<{len(g["seen_14273"])}H', *g['seen_14273']))
        for i, p in enumerate(g['players']):
            a = self.player_address(i)
            self.write(a + 0x67, self.unit_address(p['units_first_67']))
            self.write(a + 0x6b, self.unit_address(p['units_last_6b']))
            self.write(a + 0x80, p['seen_w_80'])
            self.write(a + 0x84, p['seen_h_84'])
            mu.mem_write(a + 0x108, bytes(p['alliance_108']))
            self.w8(a + 0x146, p['index_146'])
        self.write(MOVE_OBJ, MOVE_OBJ + 8)
        self.write(MOVE_OBJ + 12, 0)
        mu.mem_write(CUSTOM_SOUND, CUSTOM_SOUND_NAME.encode() + b'\0')
        for u in g['units']:
            if u is not None:
                self.write_unit(u)
        for u in g['units']:
            if u is not None and u['cargo_8a']:
                # chains after every record is written (write_unit clears the whole record, including +0x8e)
                cargo = u['cargo_8a']
                self.write(self.unit_address(u['id']) + 0x8a, self.unit_address(cargo[0]))
                for i, member in enumerate(cargo):
                    self.write(self.unit_address(member) + 0x8e, self.unit_address(cargo[i + 1]) if i + 1 < len(cargo) else 0)
        self.write_hover_cursor()

    def write_hover_cursor(self):
        g = self.g
        self.w16(GAME + 0x2cba, g['hover_2cba'])
        self.mu.mem_write(GAME + 0x2caa, struct.pack('<iii', *g['cursor_2caa']))
        self.w8(GAME + 0x2cc3, g['mode_2cc3'])

    def write_flags(self, u):
        self.write(self.unit_address(u['id']) + 0x110, u['f110'])

    def write_unit(self, u):
        uid = u['id']
        a = self.unit_address(uid)
        d = DEFS + uid * 0x250
        self.mu.mem_write(a, bytes(U))
        self.write(a, MOVE_OBJ if u['loco_0'] else 0)
        for slot, offset in enumerate((0x10, 0x2c, 0x48)):
            wa = WEAPONS + uid * 0x400 + slot * 0x130
            w = u['weapons'][slot]
            self.write(a + offset, wa)
            self.write(wa + 0x111, w['flags_111'])
            self.wf(wa + 0xc0, w['energy_c0'])
            self.wf(wa + 0xc4, w['metal_c4'])
        self.w8(a + 0x3b, u['slot1_3b'])
        self.mu.mem_write(a + 0x6a, struct.pack('<iii', u['x_6a'], u['y_6e'], u['z_72']))
        self.write(a + 0x86, self.unit_address(u['transporter_86']))
        self.write(a + 0x92, d)
        self.write(a + 0x96, self.player_address(u['player_96']))
        self.w16(a + 0xa6, u['alive_a6'])
        r = RES + uid * 0x100
        self.write(a + 0xec, r)
        self.wf(r + 0x8c, u['resources_ec']['energy_8c'])
        self.wf(r + 0x98, u['resources_ec']['metal_98'])
        self.write(a + 0xfb, u['select_fb'])
        self.w8(a + 0xff, u['owner_ff'])
        self.wf(a + 0x104, u['build_104'])
        self.w16(a + 0x108, u['health_108'])
        self.write(a + 0x110, u['f110'])
        dd = u['def_92']
        self.mu.mem_write(d, bytes(0x250))
        self.w16(d + 0x14a, dd['footprintx_14a'])
        self.write(d + 0x156, dd['buildlist_156'])
        self.write(d + 0x16e, dd['maxy_16e'])
        self.w16(d + 0x1be, dd['depth_1be'])
        self.w16(d + 0x1c0, dd['minwaterdepth_1c0'])
        wd = WEAPONS + uid * 0x400 + 3 * 0x130
        self.write(d + 0x1ee, wd)
        self.write(wd + 0x111, dd['weapon1_1ee']['flags_111'])
        self.write(d + 0x1fa, dd['maxdamage_1fa'])
        self.w8(d + 0x22a, dd['transport_size_22a'])
        self.w8(d + 0x22b, dd['transport_capacity_22b'])
        self.write(d + 0x241, dd['f241'])
        self.write(d + 0x245, dd['f245'])

    def queues(self, ids):
        out = {}
        for uid in ids:
            a = self.unit_address(uid)
            lists = [self.order_list_at(a + 0x5c), self.order_list_at(a + 0x60)]
            if lists[0] or lists[1]:
                out[str(uid)] = lists
        return out

    def order_list_at(self, head):
        result = []
        order = self.read(head)
        guard = 0
        while order:
            m = self.mu.mem_read(order, noq.ORDER_SIZE)
            x, y, z = struct.unpack_from('<iii', m, 0x22)
            u32 = lambda o: struct.unpack_from('<I', m, o)[0]
            i32 = lambda o: struct.unpack_from('<i', m, o)[0]
            result.append([self.ids[order], m[4], m[5], u32(6), u32(0xa), self.unit_ref(u32(0xe)), self.unit_ref(u32(0x16)),
                           x, y, z, u32(0x2e), u32(0x32), i32(0x36), i32(0x3a), i32(0x3e), u32(0x42), u32(0x46), u32(0x4e), u32(0x52)])
            order = u32(0x4a)
            guard += 1
            if guard > 2000:
                raise AssertionError('cyclic order list')
        return result

    def order_addresses(self, uid):
        a = self.unit_address(uid)
        out = []
        for head in (0x5c, 0x60):
            order = self.read(a + head)
            while order:
                out.append(order)
                order = self.read(order + 0x4a)
        return out


# ----------------------------------------------------------------------------------------------- select cases
def make_select_case(gen, rng):
    players = gen.players(rng.choice([2, 3, 4]), 0)
    own = rng.randrange(len(players))
    units = [None] * 7
    mode = rng.choice(MODES)
    cls = None
    if rng.random() < 0.5:
        cls = rng.choice(MODE_CLASSES.get(mode & 0xff, list(CLASSES)))
    units[1] = gen.unit(1, own, rng.randrange(3), cls)
    kind = rng.choice(['none', 'none', 'own', 'own', 'ally', 'enemy', 'enemy', 'enemy', 'random'])
    hp = own if kind == 'own' else rng.randrange(len(players))
    if kind == 'ally' and hp == own:
        hp = (own + 1) % len(players)
    if kind == 'enemy' and hp == own:
        hp = (own + 1) % len(players)
    if kind == 'ally':
        players[own]['alliance_108'][players[hp]['index_146']] = rng.choice([1, 0xff])
    elif kind == 'enemy':
        players[own]['alliance_108'][players[hp]['index_146']] = 0
    units[2] = gen.unit(2, hp, rng.randrange(3))
    units[3] = gen.unit(3, rng.randrange(len(players)), rng.randrange(3), rng.choice(['air_transport', 'ground_transport', 'random']))
    for uid in range(4, 7):
        units[uid] = gen.unit(uid, rng.randrange(len(players)), rng.randrange(3))
    if rng.random() < 0.3:
        units[2]['transporter_86'] = 3
    if rng.random() < 0.5:
        members = rng.sample(range(4, 7), rng.randint(1, 3))
        units[1]['cargo_8a'] = members
        for m in members:
            units[m]['transporter_86'] = 1 if rng.random() < 0.8 else rng.choice([0, 3])
    if rng.random() < 0.3:
        members = rng.sample(range(4, 7), rng.randint(1, 3))
        units[2]['cargo_8a'] = members
        for m in members:
            units[m]['transporter_86'] = 2 if rng.random() < 0.8 else 0
        if units[1]['cargo_8a']:
            units[1]['cargo_8a'] = [m for m in units[1]['cargo_8a'] if m not in members]
    if kind == 'own' and rng.random() < 0.6:
        units[2]['owner_ff'] = 0
    if rng.random() < 0.5:
        # bias towards passing predicates: damaged/nanoframe mobile target that fits a transport with room
        h, hd, ud = units[2], units[2]['def_92'], units[1]['def_92']
        h['health_108'] = rng.choice([1, 50, 99])
        h['loco_0'] = 1
        h['build_104'] = rng.choice([0.0, 0.0, 0.5])
        h['f110'] = (h['f110'] & ~3) | rng.choice([0, 0, 1, 2])
        hd['footprintx_14a'] = rng.choice([1, 2, 3])
        hd['minwaterdepth_1c0'] = rng.choice([-10000, -10000, 5])
        hd['f245'] &= ~0x80000 if rng.random() < 0.8 else MASK
        ud['transport_size_22a'] = rng.choice([2, 4, 8])
        ud['transport_capacity_22b'] = rng.choice([1, 3, 5])
        h['y_6e'] = rng.choice([0, 30 << 16, 60 << 16, -(20 << 16)])
    g = gen.game(units, players)
    if kind == 'own' and rng.random() < 0.5:
        g['local_player_2a42'] = units[2]['owner_ff']
    g['cursor_2caa'] = gen.cursor(g)
    if rng.random() < 0.25 and g['feature_count_14253']:
        # aim at a seen cell that holds a direct feature
        direct = [i for i, c in enumerate(g['cells_14287']) if c[0] < g['feature_count_14253']]
        if direct:
            i = rng.choice(direct)
            w = g['map_w_14233']
            x, z = (i % w) * 16 + rng.randrange(16), (i // w) * 16 + rng.randrange(16)
            g['cursor_2caa'] = [x << 16, rng.choice([0, 10 << 16]), z << 16]
            p = players[own]
            p['seen_w_80'], p['seen_h_84'] = 16, 16
            lz = (z - (g['cursor_2caa'][1] >> 17)) >> 5
            if 0 <= lz < 16:
                g['seen_14273'][16 * lz + (x >> 5)] |= 0xffff
            g['feature_flags_1426f'][g['cells_14287'][i][0]] |= 0x80
    hover = 0 if kind == 'none' else 2
    pos_null = rng.random() < 0.08 and (mode & 0xff) not in (1, 12)
    return dict(kind='select', g=g, unit=1, hover=hover, mode=mode, pos_null=pos_null, hover_kind=kind,
                range={'1': [rng.randrange(2), rng.randrange(2)]})


SEEN_W = 16


def order_would_crash(case):
    """0x43f0e0 mode 1 with a null position reaches 0x4815a0(null) only through the Left-Click reclaim recursion."""
    g, u, h = case['g'], case['g']['units'][case['unit']], case['g']['units'][case['hover']] if case['hover'] else None
    if (case['mode'] & 0xff) == 12:
        return u['def_92']['f245'] & 0x400 != 0
    if (case['mode'] & 0xff) != 1 or h is None or not h['f110'] & 0x10000000 or g['interface_37efa'] == 1:
        return False
    players = g['players']
    enemy = players[u['player_96']]['alliance_108'][players[h['player_96']]['index_146']] == 0
    f245 = u['def_92']['f245']
    return enemy and not f245 & 0x10 and f245 & 0x400 != 0


def make_edge_case(gen, rng):
    """Branch-coverage cases (added after the edge-coverage audit): feature lookups in every resurrect/reclaim path of
    both interfaces (direct in/out of count, back links to any occupant, reserved cells, cursor outside the map but inside
    the seen bitmap, flags with and without 0x80), null positions in modes 1/2, carried selectable hovers and NaN floats."""
    case = make_select_case(gen, rng)
    g = case['g']
    units = g['units']
    u, h = units[1], units[2]
    d = u['def_92']
    if rng.random() < 0.8:
        d['f245'] |= rng.choice([0x800, 0x400, 0xc00, 0xc00])
        if rng.random() < 0.7:
            d['f245'] |= 0x80
        if rng.random() < 0.5:
            d['f245'] &= ~0x10
    g['interface_37efa'] = rng.choice([0, 1, 1, 2])
    case['mode'] = rng.choice([1, 1, 1, 1, 2, 2, 12, 12])
    if rng.random() < 0.45:
        case['hover'] = 0
        case['hover_kind'] = 'none'
    w, hh = g['map_w_14233'], g['map_h_14237']
    p = g['players'][u['player_96']]
    p['seen_w_80'], p['seen_h_84'] = SEEN_W, SEEN_W
    r = rng.random()
    if r < 0.2:
        x = rng.randint(w * 16, SEEN_W * 32 - 1) if rng.random() < 0.6 else rng.randrange(w * 16)
        z = rng.randint(hh * 16, SEEN_W * 32 - 1) if rng.random() < 0.6 else rng.randrange(hh * 16)
    else:
        i = rng.randrange(w * hh)
        x, z = (i % w) * 16 + rng.randrange(16), (i // w) * 16 + rng.randrange(16)
    # negative heights too: the seen square uses s16(y) >> 1 (sign matters)
    y = rng.choice([0, 0, 6, 20, -6, -20, -64, -200])
    g['cursor_2caa'] = [(x << 16) + rng.randrange(0x10000), y << 16, (z << 16) + rng.randrange(0x10000)]
    lz, lx = (z - (y >> 1)) >> 5, x >> 5
    if rng.random() < 0.85 and 0 <= lz < SEEN_W and 0 <= lx < SEEN_W:
        g['seen_14273'][SEEN_W * lz + lx] |= 1 << (g['viewing_player_2a43'] & 31) & 0xffff or 0xffff
    g['feature_flags_1426f'] = [rng.choice([0, 0x80, 0x80, 0xff, 0x7f]) for _ in range(FEATURE_SLOTS)]
    if rng.random() < 0.5:
        g['feature_count_14253'] = rng.choice([4, 8, 12, 16])
    if case['hover'] and rng.random() < 0.3:
        # own selectable hover carried by unit 3 (with or without +0x110 0x40000000)
        h['owner_ff'] = g['local_player_2a42']
        h['f110'] |= 0x10000020
        h['build_104'] = rng.choice([0.0, 0.0, -0.0, 'NaN', 0.5])
        h['select_fb'] = 0
        h['transporter_86'] = rng.choice([3, 3, 0])
        units[3]['f110'] ^= rng.choice([0, 0x40000000])
    if rng.random() < 0.3:
        for key, record in ((('build_104',), h), (('build_104',), u), (('energy_8c', 'metal_98'), u['resources_ec']),
                            (('energy_c0', 'metal_c4'), u['weapons'][2])):
            for k in key:
                if rng.random() < 0.35:
                    record[k] = 'NaN'
        if rng.random() < 0.3:
            d['f245'] |= 0x4000
            if rng.random() < 0.5:
                case['mode'] = 4
    case['pos_null'] = rng.random() < 0.15 and (case['mode'] & 0xff) in (1, 2) and not order_would_crash(case)
    case['edge'] = True
    return case


def make_edge_group_case(gen, rng):
    """0x48d220 empty selection after removing a selectable hover that is carried, and NaN build fractions in groups."""
    case = make_group_case(gen, rng)
    g = case['g']
    p = g['players'][g['local_player_2a42']]
    first, last = p['units_first_67'], p['units_last_6b']
    if last < first:
        p['units_last_6b'] = last = first
    units = g['units']
    only = rng.randint(first, last)
    for uid in range(first, last + 1):
        units[uid]['f110'] &= ~0x10
    h = units[only]
    h['f110'] |= 0x10000030
    h['owner_ff'] = g['local_player_2a42']
    h['build_104'] = rng.choice([0.0, 'NaN', 0.0, 1.0])
    h['select_fb'] = 0
    carrier = rng.choice([0, len(units) - 1, len(units) - 1])
    h['transporter_86'] = carrier
    if carrier:
        units[carrier]['f110'] ^= rng.choice([0, 0x40000000])
    g['hover_2cba'] = only
    for uid in range(1, len(units)):
        if rng.random() < 0.15:
            units[uid]['build_104'] = 'NaN'
    total = len(units) - 1
    head = [dict(op='cursor', mode=rng.choice([1, 1, 2]), ui_mode=rng.choice([None, rng.randrange(15)]),
                 range={str(uid): [rng.randrange(2), rng.randrange(2)] for uid in range(first, last + 1)})]
    if rng.random() < 0.5:
        head.append(dict(op='select', flips=[[rng.randint(first, last), 0x10]]))
        head.append(dict(op='cursor', mode=1, ui_mode=None, range={str(uid): [1, 0] for uid in range(first, last + 1)}))
    case['ops'] = head + case['ops']
    case['edge'] = True
    return case


def run_select_case(native, case):
    g = case['g']
    native.load(g)
    native.range_answers = {int(k): v for k, v in case['range'].items()}
    ua, ha = native.unit_address(case['unit']), native.unit_address(case['hover'])
    native.write(OUT, 0x77)
    native.events = []
    ret = native.call(0x43f0e0, [OUT, case['mode'], ua, ha, 0 if case['pos_null'] else GAME + 0x2caa])
    if ret != OUT:
        raise AssertionError('0x43f0e0 did not return its out pointer')
    case['order'] = native.read8(OUT)
    case['order_events'] = native.events
    native.events = []
    case['cursor'] = s32(native.call(0x43e490, [case['mode'], ua, ha, GAME + 0x2caa]))
    case['cursor_events'] = native.events
    preds = {}
    pairs = [(1, case['hover'])] + ([(case['hover'], 1)] if case['hover'] else []) + [(1, 3), (3, 2), (1, 4)]
    for a, b in pairs:
        key = f'{a},{b}'
        aa, ba = native.unit_address(a), native.unit_address(b)
        preds[key] = [native.call(0x4899b0, [ba], this=aa) & 0xff,
                      native.call(0x489960, [ba], this=aa) & 0xff if b else None,
                      native.call(0x489a90, [ba], this=aa) & 0xff if b else None]
    case['predicates'] = preds
    return case


# ----------------------------------------------------------------------------------------------- group cases
GROUP_TYPES = [0x19, 0x1c, 0x21, 0x36, 0x37, 0x3b, 0x1d, 0x1e, 0x2c, 0x2a, 0x2b, 0x05, 0x22, 0x1f, 0x20, 0x16, 0x11, 0x0e,
               0x0f, 0x00, 0x10, 0x28, 0x25, 0x2d, 0x13, 0x14, 0x41, 0x42]


def make_group_case(gen, rng):
    nplayers = rng.choice([2, 3, 4])
    players = gen.players(nplayers, 0)
    local = rng.randrange(min(nplayers, 3))
    count = rng.choice([1, 2, 3, 4, 6, 8, 12, 16])
    first = rng.randint(1, 3)
    last = first + count - 1
    total = min(MAX_UNITS - 1, last + rng.randint(2, 6))
    units = [None] * (total + 1)
    base_x, base_z = rng.randint(0, 0x800000), rng.randint(0, 0x800000)
    spread = rng.choice([0x10000, 0x100000, 0x400000, 0x1000000, 0x7f000000])
    for uid in range(1, total + 1):
        in_range = first <= uid <= last
        player = local if in_range and rng.random() < 0.9 else rng.randrange(nplayers)
        u = gen.unit(uid, player, local if in_range and rng.random() < 0.8 else rng.randrange(3))
        if rng.random() < 0.85:
            u['x_6a'] = s32(base_x + rng.randint(-spread, spread))
            u['z_72'] = s32(base_z + rng.randint(-spread, spread))
        if in_range:
            u['f110'] = (u['f110'] & ~0x10) | (0x10 if rng.random() < 0.7 else 0)
        units[uid] = u
    g = gen.game(units, players)
    g['local_player_2a42'] = local
    if rng.random() < 0.7:
        g['viewing_player_2a43'] = local
    players[local]['units_first_67'] = first
    players[local]['units_last_6b'] = last if rng.random() < 0.95 else first - 1
    for p in range(nplayers):
        if p != local:
            players[p]['units_first_67'] = last + 1
            players[p]['units_last_6b'] = total
    g['cursor_2caa'] = [s32(base_x + rng.randint(-0x200000, 0x200000)), rng.randint(0, 0x400000), s32(base_z + rng.randint(-0x200000, 0x200000))]
    g['hover_2cba'] = rng.choice([0, 0, rng.randint(1, total), rng.randint(first, last)])
    ops = []
    if count >= 2 and rng.random() < 0.08:
        # formation radius boundary: two selected units whose second offset squares to exactly n*3000 (hi32 of 16.16)
        a, b = first, first + 1
        for uid in range(first, last + 1):
            units[uid]['f110'] &= ~0x10
        bx, bz = rng.randint(0, 0x100) << 16, rng.randint(0, 0x100) << 16
        units[a].update(x_6a=bx, z_72=bz, f110=units[a]['f110'] | 0x10)
        units[b].update(x_6a=bx + (154 << 16) + 30300, z_72=bz, f110=units[b]['f110'] | 0x10)
        ops.append(dict(op='group', input_flags=0, mode=0, type=rng.choice([0x19, 0x1c, 0x36]), pos=list(g['cursor_2caa']), p5=0, p6=0))
    for _ in range(rng.randint(3, 10)):
        ops.append(make_group_op(gen, rng, g, first, last, total))
    return dict(kind='group', g=g, ops=ops)


def make_group_op(gen, rng, g, first, last, total):
    r = rng.random()
    if r < 0.45:
        mode = rng.choice([0, 0, 0] + list(range(1, 15)) + [1, 1, 2, 3, 9, 8, 12])
        type_id = rng.choice(GROUP_TYPES + [rng.randrange(67)])
        if rng.random() < 0.05:
            type_id |= rng.choice([0x100, 0x7700, 0x12340000])
        cursor = g['cursor_2caa']
        pr = rng.random()
        if pr < 0.15:
            pos = None
        elif pr < 0.7:
            pos = list(cursor)
        else:
            pos = [s32(cursor[0] + rng.choice([0, 0x100000, -0x100000, 0x100001, rng.randint(-0x300000, 0x300000)])), cursor[1],
                   s32(cursor[2] + rng.choice([0, 0x100000, -0xfffff, rng.randint(-0x300000, 0x300000)]))]
        flags = rbits(rng, [4, 4, 8, 1, 0x10, 0x100], 0.4)
        return dict(op='group', input_flags=flags, mode=mode, type=type_id, pos=pos,
                    p5=rng.choice([0, 0, 1, 2, rng.randint(-5, 5)]), p6=rng.choice([0, 0, 1, rng.randint(-3, 3)]))
    if r < 0.55:
        return dict(op='cursor', mode=rng.choice(list(range(0, 15)) + [1, 1, 2, 3]),
                    ui_mode=rng.choice([None, None, rng.randrange(15)]),
                    range={str(uid): [rng.randrange(2), rng.randrange(2)] for uid in range(first, last + 1)})
    if r < 0.67:
        return dict(op='ack', args=[rng.choice([0, 0, 1]) for _ in range(64)])
    if r < 0.77:
        return dict(op='select', flips=[[rng.randint(1, total), rng.choice([0x10, 0x10, 0x10000000, 0x20, 0x4000])] for _ in range(rng.randint(1, 4))])
    if r < 0.85:
        return dict(op='hover', id=rng.choice([0, rng.randint(1, total), rng.randint(first, last)]))
    if r < 0.92:
        c = g['cursor_2caa']
        return dict(op='cursor_pos', pos=[s32(c[0] + rng.choice([0, 0x100000, -0x100000, rng.randint(-0x400000, 0x400000)])),
                                          c[1], s32(c[2] + rng.choice([0, 0x100000, rng.randint(-0x400000, 0x400000)]))])
    uid = rng.randint(first, last)
    return dict(op='insert', unit=uid, type=rng.choice(GROUP_TYPES), shift=rng.randrange(2), target=rng.choice([0, 0, rng.randint(1, total)]),
                pos=rng.choice([None, list(g['cursor_2caa'])]), p36=rng.randint(-2, 2), p3a=rng.randint(-2, 2),
                flags_or=rng.choice([0, 0, 0, 0x4000, 0x4]))


def run_group_case(native, case):
    g = case['g']
    native.load(g)
    p = g['players'][g['local_player_2a42']]
    ids = list(range(p['units_first_67'], p['units_last_6b'] + 1))
    all_ids = [u['id'] for u in g['units'] if u is not None]
    for op in case['ops']:
        native.events = []
        kind = op['op']
        if kind == 'group':
            native.write(INPUT + 8, op['input_flags'])
            pos_ptr = 0
            if op['pos'] is not None:
                pos_ptr = POS_ARG
                native.mu.mem_write(POS_ARG, struct.pack('<iii', *op['pos']))
            native.call(0x48cf30, [INPUT, op['mode'], op['type'], pos_ptr, op['p5'] & MASK, op['p6'] & MASK])
        elif kind == 'cursor':
            g['mode_2cc3'] = op['mode'] if op['ui_mode'] is None else op['ui_mode']
            native.write_hover_cursor()
            native.range_answers = {int(k): v for k, v in op['range'].items()}
            op['result'] = s32(native.call(0x48d220, [op['mode']]))
        elif kind == 'ack':
            replies = []
            i = 0
            for uid in all_ids:
                for order in native.order_addresses(uid):
                    arg = CUSTOM_SOUND if op['args'][i % len(op['args'])] else 0
                    i += 1
                    native.call(0x438880, [arg], this=order)
        elif kind == 'select':
            for uid, bit in op['flips']:
                u = g['units'][uid]
                u['f110'] ^= bit
                native.write_flags(u)
        elif kind == 'hover':
            g['hover_2cba'] = op['id']
            native.write_hover_cursor()
        elif kind == 'cursor_pos':
            g['cursor_2caa'] = op['pos']
            native.write_hover_cursor()
        elif kind == 'insert':
            pos_ptr = 0
            if op['pos'] is not None:
                pos_ptr = POS_ARG
                native.mu.mem_write(POS_ARG, struct.pack('<iii', *op['pos']))
            native.call(0x43adc0, [op['type'], op['shift'], native.unit_address(op['unit']), native.unit_address(op['target']),
                                   pos_ptr, op['p36'] & MASK, op['p3a'] & MASK])
            head = native.read(native.unit_address(op['unit']) + 0x5c)
            if head and op['flags_or']:
                native.write(head + 0x42, native.read(head + 0x42) | op['flags_or'])
        op['events'] = native.events
        op['queues'] = native.queues(all_ids)
        op['next_id'] = native.next_id
    return case


DEFAULT_COUNTS = [12000, 2500, 4000, 500]


def generate_cases(native, select_count, group_count, edge_select_count=0, edge_group_count=0):
    """Yields executed cases in a fixed order: random select, random group, then the edge-coverage select and group
    phases (appended so the earlier cases keep their seeds)."""
    rng = random.Random(0x43f0e0)
    gen = SceneGen(rng)
    index = 0
    plan = [(select_count, make_select_case), (group_count, make_group_case), (edge_select_count, make_edge_case),
            (edge_group_count, make_edge_group_case)]
    for count, maker in plan:
        for _ in range(count):
            case = maker(gen, rng)
            case['index'] = index
            index += 1
            if case['kind'] == 'select':
                yield run_select_case(native, case)
            else:
                # keep the initial scene: the runner mutates g for select/hover/cursor ops
                initial = json.loads(json.dumps(case['g']))
                run_group_case(native, case)
                case['g'] = initial
                yield case


def main():
    executable = Path('local/original/TotalA.exe').read_bytes()
    native = Native(executable)
    native.build_table()
    for address, name in ((0x50120c, 'Standing_FireOrder'), (0x501220, 'Standing_MoveOrder')):
        if native.cstr(address) != name:
            raise AssertionError(f'{address:#x} is not {name}')
    default_sound_ptr = native.read(0x5086e8 + 5 * 0x18)
    default_sound = native.cstr(default_sound_ptr) if 0x400000 <= default_sound_ptr < 0x600000 else f'{default_sound_ptr:#x}'
    counts = [int(a) for a in sys.argv[1:5]] + DEFAULT_COUNTS[len(sys.argv[1:5]):]
    select_count, group_count, edge_select_count, edge_group_count = counts
    cases = list(generate_cases(native, *counts))
    folder = Path('local/orders')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native-order-selector.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, default_reply_sound=default_sound,
                                                                       cases=cases)), encoding='utf-8')
    # ----- coverage -----
    cov = dict(order_by_mode={}, cursor_by_mode={}, classes={}, hover_kinds={}, predicates_true=[0, 0, 0], predicates_false=[0, 0, 0],
               range_calls=0, group_ops={}, group_issued_orders=0, formation_offsets=0, toggle_removals=0, replies=0,
               aggregate_results={}, sea_levels={}, interfaces={}, pos_null=0, dead_hover_zero=0, group_ops_without_recipient=0,
               group_modes={}, formation_unchanged=0, hover_target_passed=0, type_high_bytes=0, group_types={})
    table = noq_table(native)
    names = [e['name'] for e in table]
    table_flags = [e['flags'] for e in table]
    for case in cases:
        g = case['g']
        cov['sea_levels'][str(g['sea_level_1427f'])] = cov['sea_levels'].get(str(g['sea_level_1427f']), 0) + 1
        cov['interfaces'][str(g['interface_37efa'])] = cov['interfaces'].get(str(g['interface_37efa']), 0) + 1
        if case['kind'] == 'select':
            m = str(case['mode'])
            cov['order_by_mode'].setdefault(m, {})
            name = names[case['order']] if case['order'] else '0'
            cov['order_by_mode'][m][name] = cov['order_by_mode'][m].get(name, 0) + 1
            cov['cursor_by_mode'].setdefault(m, {})
            cov['cursor_by_mode'][m][hex(case['cursor'])] = cov['cursor_by_mode'][m].get(hex(case['cursor']), 0) + 1
            cls = g['units'][1]['cls']
            cov['classes'][cls] = cov['classes'].get(cls, 0) + 1
            cov['hover_kinds'][case['hover_kind']] = cov['hover_kinds'].get(case['hover_kind'], 0) + 1
            cov['pos_null'] += case['pos_null']
            if case['hover'] and not g['units'][2]['f110'] & 0x10000000:
                cov['dead_hover_zero'] += 1
            cov['range_calls'] += len(case['cursor_events'])
            for v in case['predicates'].values():
                for i, r in enumerate(v):
                    if r is not None:
                        cov['predicates_true' if r else 'predicates_false'][i] += 1
        else:
            previous_next = 1
            for op in case['ops']:
                allocated = op['next_id'] - previous_next
                previous_next = op['next_id']
                if op['op'] == 'group':
                    issues = [e for e in op['events'] if e[0] == 'issue']
                    cov['group_issued_orders'] += len(issues)
                    if not issues:
                        cov['group_ops_without_recipient'] += 1
                    cov['toggle_removals'] += len(issues) - allocated
                    cov['group_modes'][str(op['mode'])] = cov['group_modes'].get(str(op['mode']), 0) + 1
                    for e in issues:
                        if op['pos'] is not None and e[5] != op['pos']:
                            cov['formation_offsets'] += 1
                        if op['pos'] is not None and e[5] == op['pos'] and table_flags[e[2] & 0xff] & 2:
                            cov['formation_unchanged'] += 1
                        if e[4]:
                            cov['hover_target_passed'] += 1
                        if e[2] > 0xff:
                            cov['type_high_bytes'] += 1
                        name = names[e[2] & 0xff]
                        cov['group_types'][name] = cov['group_types'].get(name, 0) + 1
                cov['group_ops'][op['op']] = cov['group_ops'].get(op['op'], 0) + 1
                cov['replies'] += sum(1 for e in op['events'] if e[0] == 'reply')
                if op['op'] == 'cursor':
                    cov['aggregate_results'][hex(op['result'])] = cov['aggregate_results'].get(hex(op['result']), 0) + 1
    total_ops = sum(cov['group_ops'].values())
    edges = native.edge_report()
    summary = dict(
        exe_sha256=EXE_HASH, oracle='tools/native_order_selector.py', comparator='godot/compare_native_order_selector.gd',
        port='godot/order_selector.gd', trace='local/orders/native-order-selector.json (git-ignored)',
        select_cases=select_count + edge_select_count, group_cases=group_count + edge_group_count, group_operations=total_ops,
        phases=dict(random_select=select_count, random_group=group_count, edge_select=edge_select_count,
                    edge_group=edge_group_count),
        default_reply_sound=default_sound, nan_float_fields=count_nan(cases),
        branch_edges=edges,
        coverage=cov,
        stubs={'0x49abb0': 'unit range test (stdcall ret 0xc): per-unit recorded answer, call recorded',
               '0x49aa80': 'position range test (stdcall ret 0x10): per-unit recorded answer, call recorded (origin asserted == unit+0x6a)',
               '0x47fad0': 'unit reply priority queue (thiscall ret 0xc): recorded (unit, reply index, sound name), not executed',
               '0x4b4f10/0x4b4f20': 'operator new/delete: bump allocator, 0x56-byte orders get sequential ids; delete records order ids',
               '0x489800': 'clear weapon targets: recorded only', '0x48a0f0': 'aim reset: recorded only (never reached)',
               'order handlers': 'redirected to the queue oracle stub; never called by these routines'},
        unmodified=['0x43f0e0', '0x43e490', '0x4899b0', '0x489960', '0x489a90', '0x4815a0', '0x438760', '0x4f8a70', '0x438830',
                    '0x43e470', '0x48d220', '0x40c9f0', '0x48ddc0', '0x480100', '0x406c00', '0x48cf30', '0x4e43a0', '0x4e4400',
                    '0x4e43d0', '0x43afc0', '0x43adc0', '0x43a0c0', '0x4895c0', '0x43a1f0', '0x438880', '0x47f780', '0x4c5740',
                    '0x403180/0x406bf0/0x415b20/0x43bc90 order table build'],
        scope=('Select cases: one unit (17 class templates with random flag flips), hover none/own/ally/enemy/random with its own '
               'definition, a transporter and cargo chains (members with and without the matching +0x86), 2-4 players with '
               'random alliance bytes and occasionally duplicated +0x146 indices, seen bitmap dims 0/1/4/8/16/0x80000000, feature '
               'grids 4..16 cells with direct, back-linked (0xfffe), reserved and out-of-count occupants, sea level 0..255, '
               'interface 0/1/2/0x101, modes 0..15 plus 0x101/0x203/0xff, null pos outside modes 1 and 12, float fields '
               'including -0.0 and 1e-7; direct predicate calls for five unit pairs. Group cases: 1-16 local units in the '
               'player range (occasionally an empty range), selection bits, hover of own/other units, 3-10 operations of group '
               'issue (mode 0 with types incl. high bytes, modes 1-14, shift, null/cursor/offset positions, p5/p6), cursor '
               'aggregation (UI mode byte equal or different), acknowledgement passes over every queued order, selection '
               'flips, hover and cursor moves, and direct 0x43adc0 inserts with idle/protected flags. Edge phases (added by '
               'the branch-coverage audit): feature lookups in every resurrect/reclaim path of both interfaces, cursors '
               'outside the map inside the seen bitmap, null positions in modes 1/2 that do not reach 0x4815a0, carried '
               'selectable hovers, NaN float fields (build, resources, D-gun cost), and 0x48d220 with only the carried '
               'selectable hover selected. Excluded: null pos into 0x4815a0 (crashes), handler bodies, the real range '
               'tests and reply queue, save/load.'))
    Path('analysis/native-order-selector-validation.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(f'NATIVE_ORDER_SELECTOR {select_count + edge_select_count} select cases, {group_count + edge_group_count} group '
          f'cases / {total_ops} operations; ops {cov["group_ops"]}; replies {cov["replies"]}; default reply sound {default_sound}')
    print(f'NATIVE_ORDER_SELECTOR branch edges {edges["covered"]} / {edges["total"]} covered, '
          f'{edges["uncovered_reachable"]} uncovered edges not proven unreachable')
    for line in edges['uncovered']:
        print('  uncovered', line)


def count_nan(cases):
    found = 0
    stack = [c['g'] for c in cases]
    while stack:
        v = stack.pop()
        if isinstance(v, dict):
            stack.extend(v.values())
        elif isinstance(v, list):
            stack.extend(v)
        elif v == 'NaN':
            found += 1
    return found


def noq_table(native):
    begin, end = native.read(noq.TABLE_BEGIN), native.read(noq.TABLE_END)
    return [dict(name=native.cstr(native.read(begin + i * 0x19 + 0x15)), flags=native.read(begin + i * 0x19 + 0x11))
            for i in range((end - begin) // 0x19)]


if __name__ == '__main__':
    main()
