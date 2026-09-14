"""Original AI brain plumbing oracle: 0x408cb0 construction, 0x408830 group assignment, 0x408c40 brain tick.

Runs the ORIGINAL x86 in Unicorn (no game startup) and writes local/ai/native-ai-groups.json (git-ignored trace)
plus analysis/native-ai-groups-validation.json (summary, stubs, scope).

Part 1 - assign_groups: 0x408830 runs unmodified over synthetic player unit ranges (player+0x67 first unit,
player+0x6b last unit INCLUSIVE, stride 0x118) and calls the ORIGINAL 0x480250 set-group routine, which edits the
per-player group vectors at [player+0x78]+k*0x20+0x14/+0x18/+0x1c (begin/end/capacity).
Part 2 - construction: the ORIGINAL 0x408cb0 (with 0x407350 and 0x407d40 sub-constructors and the 0x4e43a0 ftol)
builds the brain; the handler table (vtable, think, group pointer, parameters, wakes) is dumped from memory.
Part 3 - cadence: the ORIGINAL 0x408c40 runs over tick sequences. assign_groups 0x408830/0x480250 run unmodified.
Think functions run their ORIGINAL prologues (including the 0x4b6c30 draws of groups 8 and 9) up to the
instruction after the wake store, then return to 0x408c40 with callee-saved registers restored.
Part 4 - creation word: the ORIGINAL unit initialiser 0x485a40 runs whole (no stubs besides operator new/delete, not
reached); the unit+0x110 word it leaves is recorded for AIBrain.creation_flags.

Stubs (every replaced boundary):
  0x4b4f10 operator new (cdecl): bump allocator in an oracle heap (constructor and vector growth only).
  0x4b4f20 operator delete (cdecl): no-op.
  0x4089a0 weapon scheduler (thiscall ret 4): recorder of the allow_commandfire argument.
  Think bodies after the wake store (0x4086e8, 0x407801, 0x407a10, 0x408127, 0x407b13, 0x407ebb): forced return.
  0x407380 (group 5 think) is a bare `ret` and runs unmodified.
"""
import json
from pathlib import Path
import random
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'local/python-deps'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hashlib
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDI, UC_X86_REG_EIP,
                               UC_X86_REG_ESI, UC_X86_REG_ESP, UC_X86_REG_EBP, UC_X86_REG_FPCW, UC_X86_REG_FPSW,
                               UC_X86_REG_FPTAG)
from inspect_install import inspect_pe

EXE_HASH = '3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e'
GAME_POINTER = 0x511de8
RNG_STATE = 0x51fc88
GAME = 0x1400000
TICK = GAME + 0x38a47
MAP_W = GAME + 0x14223
MAP_H = GAME + 0x14227
WORK = 0x2000000
PLAYER = WORK
UNITS = WORK + 0x1000
UNIT_SIZE = 0x118
DEFS = WORK + 0x20000
DEF_SIZE = 0x300
GROUPS = WORK + 0x40000
VECTORS = WORK + 0x41000
VECTOR_CAPACITY = 128
HEAP = WORK + 0x80000
STACK_TOP = 0x2ff0000
STOP = 0x2ff8000
MAX_UNITS = 96
DEF_RECORD = 0x249   # 0x485a4b: type * 65 * 9

# think address -> (group kind, address after the wake store)
THINK_STOPS = {0x4086d0: 0x4086e8, 0x4077e0: 0x407801, 0x4079f0: 0x407a10, 0x408100: 0x408127,
               0x407ae0: 0x407b13, 0x407e90: 0x407ebb}
NOOP_THINK = 0x407380


def s32(value):
    value &= 0xffffffff
    return value - 0x100000000 if value & 0x80000000 else value


class Native:
    def __init__(self, executable):
        if hashlib.sha256(executable).hexdigest() != EXE_HASH:
            raise ValueError('This oracle only supports the recorded executable SHA-256')
        self.mu = Uc(UC_ARCH_X86, UC_MODE_32)
        self.mu.mem_map(0x400000, 0x200000)
        self.mu.mem_write(0x400000, executable[:1024])
        for section in inspect_pe(executable)['sections']:
            self.mu.mem_write(0x400000 + section['rva'], executable[section['raw_offset']:section['raw_offset'] + section['raw_size']])
        self.mu.mem_map(GAME, 0x40000)
        self.mu.mem_map(WORK, 0x100000)
        self.mu.mem_map(0x2f00000, 0x100000)
        self.mu.reg_write(UC_X86_REG_FPCW, 0x37f)
        self.mu.reg_write(UC_X86_REG_FPSW, 0)
        self.mu.reg_write(UC_X86_REG_FPTAG, 0xffff)
        self.write(GAME_POINTER, GAME)
        self.mu.mem_write(STOP, b'\xc3')
        self.heap = HEAP
        self.mu.mem_write(0x4b4f10, b'\xc3')
        self.mu.mem_write(0x4b4f20, b'\xc3')
        self.mu.mem_write(0x4089a0, b'\xc2\x04\x00')
        self.mu.hook_add(UC_HOOK_CODE, self.allocate, begin=0x4b4f10, end=0x4b4f10)
        self.mu.hook_add(UC_HOOK_CODE, self.weapons, begin=0x4089a0, end=0x4089a0)
        self.mu.hook_add(UC_HOOK_CODE, self.set_group, begin=0x480250, end=0x480250)
        self.mu.hook_add(UC_HOOK_CODE, self.assign, begin=0x408830, end=0x408830)
        self.mu.hook_add(UC_HOOK_CODE, self.noop_think, begin=NOOP_THINK, end=NOOP_THINK)
        for entry, stop in THINK_STOPS.items():
            self.mu.hook_add(UC_HOOK_CODE, self.think_entry, begin=entry, end=entry)
            self.mu.hook_add(UC_HOOK_CODE, self.think_stop, begin=stop, end=stop)
        self.events = []
        self.saved = None
        self.allocations = 0

    def read(self, address):
        return struct.unpack('<I', self.mu.mem_read(address, 4))[0]

    def write(self, address, value):
        self.mu.mem_write(address, struct.pack('<I', value & 0xffffffff))

    def call(self, address, args, this):
        sp = STACK_TOP - (len(args) + 1) * 4
        self.write(sp, STOP)
        for i, value in enumerate(args):
            self.write(sp + 4 + i * 4, value)
        self.mu.reg_write(UC_X86_REG_ESP, sp)
        self.mu.reg_write(UC_X86_REG_ECX, this)
        self.mu.emu_start(address, STOP, count=5000000)
        if self.mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError(f'{address:#x} did not return')
        return self.mu.reg_read(UC_X86_REG_EAX)

    def arg(self, index):
        return self.read(self.mu.reg_read(UC_X86_REG_ESP) + 4 + 4 * index)

    def allocate(self, mu, address, size, data):
        count = self.arg(0)
        self.allocations += 1
        mu.reg_write(UC_X86_REG_EAX, self.heap)
        self.mu.mem_write(self.heap, bytes(count))
        self.heap = (self.heap + count + 15) & ~7

    def weapons(self, mu, address, size, data):
        self.events.append(['weapons', self.arg(0)])

    def set_group(self, mu, address, size, data):
        unit = self.arg(0)
        self.events.append(['set_group', (unit - UNITS) // UNIT_SIZE, s32(self.arg(1))])

    def assign(self, mu, address, size, data):
        self.events.append(['assign'])

    def noop_think(self, mu, address, size, data):
        handler = mu.reg_read(UC_X86_REG_ECX)
        self.events.append(['think', NOOP_THINK, self.read(handler + 0xc), self.read(RNG_STATE)])

    def think_entry(self, mu, address, size, data):
        registers = {r: mu.reg_read(r) for r in (UC_X86_REG_EBX, UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP)}
        self.saved = (address, mu.reg_read(UC_X86_REG_ESP), mu.reg_read(UC_X86_REG_ECX), registers, self.read(RNG_STATE))

    def think_stop(self, mu, address, size, data):
        entry, esp, handler, registers, rng_before = self.saved
        if THINK_STOPS[entry] != address:
            raise AssertionError('think stop does not match entry')
        self.events.append(['think', entry, self.read(handler + 0xc), self.read(RNG_STATE)])
        for register, value in registers.items():
            mu.reg_write(register, value)
        mu.reg_write(UC_X86_REG_ESP, esp + 4)
        mu.reg_write(UC_X86_REG_EIP, self.read(esp))
        self.saved = None

    # ----- world image -----
    def reset_work(self):
        self.mu.mem_write(WORK, bytes(0x80000))
        self.heap = HEAP
        self.write(PLAYER + 0x78, GROUPS)
        for k in range(10):
            base = VECTORS + k * VECTOR_CAPACITY * 4
            self.write(GROUPS + k * 0x20 + 0x14, base)
            self.write(GROUPS + k * 0x20 + 0x18, base)
            self.write(GROUPS + k * 0x20 + 0x1c, base + VECTOR_CAPACITY * 4)

    def load_units(self, case):
        for index, unit in enumerate(case['units']):
            address = UNITS + index * UNIT_SIZE
            definition = DEFS + index * DEF_SIZE
            self.write(address + 0x92, definition)
            self.write(address + 0x96, PLAYER)
            self.write(address + 0xac, unit['group'])
            self.write(address + 0x110, unit['flags110'])
            d = unit['definition']
            self.write(definition + 0x241, d['flags241'])
            self.write(definition + 0x245, d['flags245'])
            self.mu.mem_write(definition + 0x1c0, struct.pack('<h', d['minwaterdepth']))
        for k, members in enumerate(case['group_vectors']):
            base = self.read(GROUPS + k * 0x20 + 0x14)
            for i, member in enumerate(members):
                self.write(base + 4 * i, UNITS + member * UNIT_SIZE)
            self.write(GROUPS + k * 0x20 + 0x18, base + 4 * len(members))
        self.write(PLAYER + 0x67, UNITS + case['first'] * UNIT_SIZE)
        self.write(PLAYER + 0x6b, UNITS + case['last'] * UNIT_SIZE)

    def dump_units(self, count):
        flags, groups = [], []
        for index in range(count):
            address = UNITS + index * UNIT_SIZE
            flags.append(self.read(address + 0x110))
            groups.append(s32(self.read(address + 0xac)))
        vectors = []
        for k in range(10):
            begin, end = self.read(GROUPS + k * 0x20 + 0x14), self.read(GROUPS + k * 0x20 + 0x18)
            vectors.append([(self.read(p) - UNITS) // UNIT_SIZE for p in range(begin, end, 4)])
        return flags, groups, vectors

    def run_assign(self, case):
        self.reset_work()
        self.load_units(case)
        brain = WORK + 0x7f000
        self.write(brain, PLAYER)
        self.events = []
        self.call(0x408830, [], brain)
        flags, groups, vectors = self.dump_units(len(case['units']))
        return dict(flags110=flags, groups=groups, group_vectors=vectors,
                    calls=[e[1:] for e in self.events if e[0] == 'set_group'])

    def construct(self, width, height, side):
        self.reset_work()
        self.write(MAP_W, width)
        self.write(MAP_H, height)
        self.mu.mem_write(PLAYER + 0x146, bytes([side]))
        brain = self.heap
        self.heap += 0x40
        self.call(0x408cb0, [PLAYER], brain)
        return brain

    def dump_brain(self, brain):
        slots = []
        for slot in range(10):
            handler = self.read(brain + 0x11 + 4 * slot)
            if handler == 0:
                slots.append(None)
                continue
            vtable = self.read(handler)
            group_pointer = self.read(handler + 8)
            entry = dict(vtable=vtable, think=self.read(vtable), destructor=self.read(vtable + 4),
                         brain_ok=self.read(handler + 4) == brain, group=(group_pointer - GROUPS) // 0x20,
                         group_offset_exact=(group_pointer - GROUPS) % 0x20 == 0,
                         wake=self.read(handler + 0xc), side=self.read(handler + 0x10))
            if vtable == 0x4fc988:
                entry['params'] = [s32(self.read(handler + o)) for o in (0x14, 0x18, 0x1c, 0x20, 0x24)]
            elif vtable == 0x4fc990:
                entry['params'] = [s32(self.read(handler + 0x14))]
            elif vtable == 0x4fc9a0:
                entry['params'] = [s32(self.read(handler + o)) for o in range(0x14, 0x3c, 4)]
            slots.append(entry)
        return dict(player_ok=self.read(brain) == PLAYER, side=self.mu.mem_read(brain + 4, 1)[0],
                    countdown=s32(self.read(brain + 5)), field9=s32(self.read(brain + 9)),
                    block_tick=s32(self.read(brain + 0xd)), weapon_cursor=s32(self.read(brain + 0x39)), slots=slots)

    def run_creation(self, case):
        """ORIGINAL unit initialiser 0x485a40(unit, a1..a4) (stdcall ret 0x14), including its 0x4b6c30 draws,
        0x48a160/0x489800 weapon resets, 0x401070 and the final 0x480250(unit, 0). Returns the unit+0x110 word."""
        self.reset_work()
        unit = UNITS
        definition = DEFS + case['type'] * DEF_RECORD
        self.write(GAME + 0x1439b, DEFS)
        self.mu.mem_write(definition, bytes(case['definition_bytes']))
        self.mu.mem_write(definition + 0x22e, bytes([case['byte22e'], case['bmcode']]))
        self.write(definition + 0x241, case['flags241'])
        self.mu.mem_write(unit + 0xa6, struct.pack('<H', case['type']))
        self.write(unit + 0x96, PLAYER)
        self.write(unit + 0x110, case['flags110'])
        self.write(unit + 0x114, case['flags114'])
        self.mu.mem_write(PLAYER + 0x146, bytes([case['owner_side']]))
        self.mu.mem_write(GAME + 0x2a43, bytes([case['local_side']]))
        self.write(RNG_STATE, case['seed'])
        self.events = []
        self.call(0x485a40, [unit, case['args'][0], case['args'][1], case['args'][2], case['args'][3]], 0)
        if [e for e in self.events if e[0] == 'set_group'] != [['set_group', 0, 0]]:
            raise AssertionError('0x485a40 did not end with 0x480250(unit, 0)')
        return self.read(unit + 0x110)


def random_definition(rng):
    flags241 = rng.getrandbits(32) & ~0x840
    flags245 = rng.getrandbits(32) & ~0x1000
    if rng.random() < 0.3:
        flags241 |= 0x40
    if rng.random() < 0.3:
        flags241 |= 0x800
    if rng.random() < 0.25:
        flags245 |= 0x1000
    depth = rng.choice([-10000, -10000, -1, 0, 0, 1, 2, 10, 255, 256, 32767, -32768, rng.randrange(-32768, 32768)])
    return dict(flags241=flags241, flags245=flags245, minwaterdepth=depth)


def random_unit(rng, profile):
    flags = rng.getrandbits(32)
    flags = flags | 0x20 if rng.random() < 0.85 else flags & ~0x20
    structure = profile.get('structure', rng.random() < 0.3)
    armed = profile.get('armed', rng.random() < 0.5)
    flags = (flags | 0x20000000) if structure else (flags & ~0x20000000)
    flags = (flags | 0x80000000) if armed else (flags & ~0x80000000)
    definition = random_definition(rng)
    for key, bit in (('builder', 0x40), ('canfly', 0x800)):
        if key in profile:
            definition['flags241'] = (definition['flags241'] | bit) if profile[key] else (definition['flags241'] & ~bit)
    if 'cancapture' in profile:
        definition['flags245'] = (definition['flags245'] | 0x1000) if profile['cancapture'] else (definition['flags245'] & ~0x1000)
    if 'minwaterdepth' in profile:
        definition['minwaterdepth'] = profile['minwaterdepth']
    if 'flag20' in profile:
        flags = (flags | 0x20) if profile['flag20'] else (flags & ~0x20)
    group = 0 if rng.random() < 0.7 else rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0x100, 0x10000, -2])
    group = profile.get('group', group)
    return dict(flags110=flags, group=group, definition=definition, type=rng.randrange(1, 400))


PROFILES = [
    dict(name='structure-armed', structure=True, armed=True, group=0, flag20=True),
    dict(name='structure-unarmed', structure=True, armed=False, group=0, flag20=True),
    dict(name='land-builder', structure=False, builder=True, canfly=False, minwaterdepth=-10000, group=0, flag20=True),
    dict(name='air-builder', structure=False, builder=True, canfly=True, minwaterdepth=-10000, group=0, flag20=True),
    dict(name='sea-builder', structure=False, builder=True, canfly=False, minwaterdepth=15, group=0, flag20=True),
    dict(name='flyer', structure=False, builder=False, canfly=True, group=0, flag20=True),
    dict(name='ship-positive', structure=False, builder=False, canfly=False, minwaterdepth=20, group=0, flag20=True),
    dict(name='ship-zero-depth', structure=False, builder=False, canfly=False, minwaterdepth=0, group=0, flag20=True),
    dict(name='negative-depth-armed', structure=False, builder=False, canfly=False, minwaterdepth=-1, armed=True, group=0, flag20=True),
    dict(name='land-unarmed', structure=False, builder=False, canfly=False, minwaterdepth=-10000, armed=False, group=0, flag20=True),
    dict(name='commander', structure=False, builder=True, cancapture=True, armed=True, minwaterdepth=-10000, group=0, flag20=True),
    dict(name='already-grouped', flag20=True),
    dict(name='flag20-clear', flag20=False),
]


def assign_cases(rng):
    cases = []
    for index in range(600):
        count = rng.choice([0, 1, 2, rng.randrange(3, 16), rng.randrange(16, MAX_UNITS)])
        if index < len(PROFILES) * 8:
            profile = PROFILES[index % len(PROFILES)]
            category = profile['name']
            if category == 'already-grouped':
                profile = dict(profile, group=rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0x100]))
            count = max(count, 4)
        else:
            profile, category = {}, 'random'
        units = [random_unit(rng, profile if rng.random() < 0.7 else {}) for _ in range(max(count, 1))]
        total = len(units)
        mode = rng.choice(['all', 'all', 'sub', 'empty'])
        if mode == 'all':
            first, last = 0, total - 1
        elif mode == 'sub':
            first = rng.randrange(total)
            last = rng.randrange(first, total)
        else:
            first = rng.randrange(0, total + 1)
            last = first - 1
        vectors = [[] for _ in range(10)]
        order = list(range(len(units)))
        rng.shuffle(order)
        for i in order:
            g = units[i]['group']
            if 0 <= g <= 9 and rng.random() > 0.08:
                vectors[g].append(i)
        cases.append(dict(category=category, first=first, last=last, units=units, group_vectors=vectors))
    return cases


def cadence_sequences(rng):
    sequences = []
    starts = [0, 0, 1, 29, rng.randrange(1000000), rng.randrange(1000000), 0x7fffff80, 0xfffffd00]
    for index in range(32):
        start = starts[index] if index < len(starts) else rng.randrange(0, 5000000)
        ticks = 1500 if index < 8 else rng.randrange(200, 1200)
        segments = []
        t = 0
        while t < ticks:
            length = rng.choice([ticks, rng.randrange(30, 400)]) if index > 1 else ticks
            if index == 0:
                mode = (1, 2)
            else:
                mode = rng.choice([(1, 2), (1, 2), (1, 2), (0, 2), (1, 1), (1, 3), (1, 0)])
            segments.append([t, mode[0], mode[1]])
            t += length
        units = [random_unit(rng, dict(group=0)) for _ in range(rng.randrange(0, 12))]
        perturb = sorted(rng.sample(range(ticks), rng.randrange(0, 12))) if index > 2 else []
        sequences.append(dict(start_tick=start, ticks=ticks, seed=rng.choice([1, 0x7ffffffe, rng.randrange(1, 0x7fffffff)]),
                              initial_countdown=rng.choice([30, 30, 1, 0, -5, rng.randrange(1, 60)]) if index > 0 else 30,
                              width=rng.choice([1024, 2048, 4096, 1536, 1025, 8000, 7]), height=rng.choice([1024, 2048, 3072, 1023, 5000]),
                              side=rng.randrange(10), segments=segments, units=units,
                              perturb=[[t, rng.randrange(0, 0x80000000)] for t in perturb]))
    return sequences


def creation_cases(rng):
    cases = []
    for index in range(400):
        flags241 = rng.getrandbits(32)
        for bit in (0x10000, 0x200, 0x1, 0x2, 0x4, 0x8, 0x10, 0x80):
            flags241 = (flags241 | bit) if rng.random() < 0.5 else (flags241 & ~bit)
        if index % 5 == 0:
            flags241 &= 0x1ffff   # no high noise: bit 16 alone decides bit 31
        owner = rng.randrange(10)
        cases.append(dict(flags110=rng.choice([0, 0xffffffff, rng.getrandbits(32), rng.getrandbits(32)]),
                          flags114=rng.getrandbits(32), flags241=flags241 & 0xffffffff,
                          bmcode=rng.choice([0, 0, 1, 1, 2, 255, rng.randrange(256)]),
                          byte22e=rng.choice([0, 1, 2, 3, 255, rng.randrange(256)]),
                          owner_side=owner, local_side=owner if rng.random() < 0.5 else rng.randrange(10),
                          type=rng.randrange(1, 60), seed=rng.randrange(1, 0x7fffffff),
                          definition_bytes=[rng.randrange(256) for _ in range(DEF_RECORD)],
                          args=[rng.getrandbits(31), rng.getrandbits(31), rng.getrandbits(31), rng.choice([0, 1, rng.getrandbits(32)])]))
    return cases


def run_sequence(native, sequence):
    brain = native.construct(sequence['width'], sequence['height'], sequence['side'])
    constructed = native.dump_brain(brain)
    case = dict(units=sequence['units'], group_vectors=[[i for i, u in enumerate(sequence['units'])]] + [[] for _ in range(9)],
                first=0, last=len(sequence['units']) - 1)
    native.load_units(case)
    native.write(brain + 5, sequence['initial_countdown'])
    native.write(RNG_STATE, sequence['seed'])
    perturb = {t: value for t, value in sequence['perturb']}
    records = []
    segment = 0
    for offset in range(sequence['ticks']):
        while segment + 1 < len(sequence['segments']) and sequence['segments'][segment + 1][0] <= offset:
            segment += 1
        _, present, kind = sequence['segments'][segment]
        native.write(PLAYER, present)
        native.mu.mem_write(PLAYER + 0x73, bytes([kind]))
        if offset in perturb:
            native.write(RNG_STATE, perturb[offset])
        tick = (sequence['start_tick'] + offset) & 0xffffffff
        native.write(TICK, tick)
        rng_before = native.read(RNG_STATE)
        native.events = []
        native.call(0x408c40, [], brain)
        wakes = [native.read(native.read(brain + 0x11 + 4 * s) + 0xc) if native.read(brain + 0x11 + 4 * s) else None for s in range(10)]
        records.append(dict(tick=tick, present=present, type=kind, rng_before=rng_before, rng_after=native.read(RNG_STATE),
                            countdown=s32(native.read(brain + 5)), wakes=wakes, events=native.events))
    flags, groups, vectors = native.dump_units(len(sequence['units']))
    return dict(constructed=constructed, records=records, final_units=dict(flags110=flags, groups=groups, group_vectors=vectors))


def main():
    native = Native(Path('local/original/TotalA.exe').read_bytes())
    rng = random.Random(0x408830)
    cases = assign_cases(rng)
    for case in cases:
        case['expected'] = native.run_assign(case)
    sequences = cadence_sequences(random.Random(0x408c40))
    for sequence in sequences:
        sequence['expected'] = run_sequence(native, sequence)
    creations = creation_cases(random.Random(0x485a40))
    for case in creations:
        case['expected_flags110'] = native.run_creation(case)
    folder = Path('local/ai')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native-ai-groups.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, assign_cases=cases, sequences=sequences,
                                                                  creation_cases=creations)), encoding='utf-8')
    categories = {}
    outcome = {}
    for case in cases:
        categories[case['category']] = categories.get(case['category'], 0) + 1
        for _, group in case['expected']['calls']:
            outcome[str(group)] = outcome.get(str(group), 0) + 1
    think_calls = {}
    rng_draw_ticks = 0
    for sequence in sequences:
        for record in sequence['expected']['records']:
            if record['rng_after'] != record['rng_before']:
                rng_draw_ticks += 1
            for event in record['events']:
                if event[0] == 'think':
                    think_calls[hex(event[1])] = think_calls.get(hex(event[1]), 0) + 1
    summary = dict(exe_sha256=EXE_HASH, oracle='tools/native_ai_groups.py', comparator='godot/compare_native_ai_groups.gd',
                   trace='local/ai/native-ai-groups.json (git-ignored)',
                   assign_cases=len(cases), assign_categories=categories, set_group_calls_by_group=outcome,
                   assigned_units=sum(len(c['units']) for c in cases),
                   sequences=len(sequences), ticks=sum(s['ticks'] for s in sequences), think_calls=think_calls,
                   ticks_with_rng_draws=rng_draw_ticks,
                   creation_cases=len(creations),
                   stubs={'0x4b4f10': 'operator new -> bump allocator (brain/handler objects only; group vectors pre-reserved with capacity 128)',
                          '0x4b4f20': 'operator delete -> no-op (not reached)',
                          '0x4089a0': 'weapon scheduler (thiscall ret 4) -> records allow_commandfire argument',
                          'think bodies': 'original prologue executed up to the instruction after the wake store (0x4086e8, 0x407801, 0x407a10, 0x408127, 0x407b13, 0x407ebb), then forced return with ebx/esi/edi/ebp/esp restored; 0x407380 (group 5) runs unmodified'},
                   unmodified=['0x408830 assign_groups', '0x480250 set group (swap-remove / append)', '0x406c10/0x406c40 vector helpers',
                               '0x408cb0 brain constructor', '0x407350/0x407d40 handler constructors', '0x4e43a0 ftol', '0x408c40 brain tick',
                               '0x4b6c30 RNG', '0x485a40 unit initialiser (with 0x48a160, 0x489800, 0x401070, 0x480250)'],
                   scope=('Synthetic player unit ranges (first..last inclusive, empty ranges, sub-ranges), random flags110 incl. bits 18-21, '
                          'def+0x241 builder/canfly, def+0x245 cancapture, signed word def+0x1c0 minwaterdepth, group dword values incl. -1/0x100; '
                          'brain tick over 32 tick sequences with player [p]/type toggles, countdown values 30/1/0/negative, tick starts near '
                          '0x7fffffff and 0xfffffd00 (unsigned wake compare), and external RNG perturbations. '
                          'Unit creation word: 400 runs of the whole 0x485a40 initialiser with random prior flags110, def+0x241, '
                          'bmcode def+0x22f, def+0x22e, owner side vs game+0x2a43 and random remaining definition bytes; '
                          'weapon records zeroed. '
                          'Excluded: caller loop 0x464f80 (player filters are disassembly-verified only), think bodies after the wake store, '
                          'weapon scheduler, knowledge refresh 0x40b2c0, vector growth/allocation path of 0x480250.'))
    Path('analysis/native-ai-groups-validation.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(f'NATIVE_AI_GROUPS {len(cases)} assign cases, {len(sequences)} sequences / {summary["ticks"]} ticks, '
          f'{len(creations)} creation cases; think calls {think_calls}; '
          f'set_group by group {outcome}; {native.allocations} allocations')


if __name__ == '__main__':
    main()
