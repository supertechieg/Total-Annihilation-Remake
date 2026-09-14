"""Original order-queue bookkeeping oracle (TotalA.exe 0x43adc0 insert, 0x43afc0 shift toggle, 0x43b7c0/0x43bad0 dispatch).

Runs the ORIGINAL x86 in Unicorn (no game startup) and writes:
  local/orders/order-table.json          the 67-entry order table built by the ORIGINAL static initialisers
                                         0x403180/0x406bf0/0x415b20 -> 0x43bc90 (vector append + sort 0x43c020/stricmp)
  local/orders/native-order-queue.json   randomized operation sequences with full queue dumps after every operation
  analysis/native-order-queue-validation.json  summary, stubs, scope

Unmodified native code exercised by the sequences:
  0x43a0c0 order constructor, 0x4895c0/0x489690/0x489650 target reference link/unlink, 0x43a1f0 destroy (partly, see stubs),
  0x43adc0 insert, 0x43afc0 shift toggle / issue, 0x43b7c0 main dispatcher (incl. idle order creation and 0x43ac60),
  0x43bad0 background dispatcher, 0x439f80 remove, 0x439eb0 clear-all, 0x439fe0 rotate-to-tail, 0x43a020 patrol origin
  append, 0x439e30 find by type, 0x439d80 counted-build sum, 0x43b0b0 factory count, 0x43acb0 push-front-inherit,
  0x43ad10 append, 0x43ad50 marker insert, 0x4b6c30 RNG.

Stubs (every replaced boundary):
  0x4b4f10 operator new (cdecl): bump allocator; 0x56-byte order allocations get sequential ids (the port's id counter).
  0x4b4f20 operator delete (cdecl): no-op that records the freed order id (addresses are never reused inside a sequence).
  order handlers (table +4): every table entry's handler pointer is redirected, AFTER the table dump, to one stub. The stub
      records the call (order id, type, state, ev, pending, wake, flags) and applies a scripted action: OR bits into
      mask/pending/flags, optionally set wake = tick + d, optionally construct + push-front a new order through the ORIGINAL
      0x43a0c0 + 0x43acb0 (x86 thunk), then returns the scripted code (0-9, or >9). Calls from 0x43a1f0 (ev=2 destroy
      notification, return address 0x43a21e) are recorded but not scripted.
  0x43a227..0x43a25d StopBuilding block (COB StopBuilding script + 0x456190) skipped, recorded as stop_building.
  0x489800 clear weapon targets (thiscall ret 4): recorded, not executed.
  0x48a0f0 weapon aim reset (stdcall ret 8): recorded (slot), not executed.
  unit+0 (movement object) is 0, so the destroy goal-cancel block 0x43a264..0x43a2a4 is skipped natively (goal +0x52 stays 0).
Handler scripts stop runaway same-tick loops: after 8 handler calls within one operation the action is forced to code 3,
after 16 to code 7 (main) / 6 (background). Code 3 alone is not enough near tick 0xffffffff: wake = tick+rand+30 wraps below
the tick, so the native dispatcher re-runs the head forever in the same tick (a real, practically unreachable hang).
"""
import hashlib
import json
from pathlib import Path
import random
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'local/python-deps'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ECX, UC_X86_REG_EIP, UC_X86_REG_ESI, UC_X86_REG_ESP
from inspect_install import inspect_pe

EXE_HASH = '3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e'
GAME_POINTER = 0x511de8
TABLE_BEGIN = 0x512344
TABLE_END = 0x512348
RNG_STATE = 0x51fc88
GAME = 0x1400000
TICK = GAME + 0x38a47
WORK = 0x2000000
PLAYER = WORK
DEF = WORK + 0x800
UNIT = WORK + 0x1000
TARGETS = WORK + 0x2000
TARGET_COUNT = 6           # ids 1..6; id 6 is a dead unit (+0xa6 == 0)
POS_SLOTS = WORK + 0x8000
VARS = 0x2ff8100
THUNK = 0x2ff8200
HEAP = WORK + 0x10000
HEAP_END = WORK + 0x100000
TABLE_HEAP = 0x3000000
STACK_TOP = 0x2ff0000
STOP = 0x2ff8000
STUB = 0x2ff8010
UNIT_SIZE = 0x118
ORDER_SIZE = 0x56
FORCE_AFTER = 8

RET_DESTROY_CB = 0x43a21e
RET_MAIN = 0x43b880
RET_BG = 0x43bb25

V_TYPE, V_TARGET, V_POS, V_P36, V_P3A, V_CODE, V_UNIT = (VARS + 4 * i for i in range(7))

INTERESTING_TYPES = [0x19, 0x1c, 0x2c, 0x28, 0x25, 0x2a, 0x2b, 0x15, 0x12, 0x0a, 0x41, 0x0c, 0x18, 0x05, 0x00, 0x0b,
                     0x16, 0x1f, 0x42, 0x27, 0x29, 0x26, 0x1a, 0x37, 0x3f]


def s32(value):
    value &= 0xffffffff
    return value - 0x100000000 if value & 0x80000000 else value


def thunk_bytes():
    code = bytearray()

    def call(target):
        code.extend(b'\xe8' + struct.pack('<i', target - (THUNK + len(code) + 5)))

    def push_mem(address):
        code.extend(b'\xff\x35' + struct.pack('<I', address))

    code.extend(b'\x6a\x56')                 # push 0x56
    call(0x4b4f10)                            # operator new
    code.extend(b'\x83\xc4\x04')             # add esp, 4
    code.extend(b'\x6a\x00')                 # push 0 (p3e)
    for address in (V_P3A, V_P36, V_POS, V_TARGET, V_TYPE):
        push_mem(address)
    code.extend(b'\x8b\xc8')                 # mov ecx, eax
    call(0x43a0c0)                            # constructor (thiscall ret 0x18)
    code.extend(b'\x50')                     # push eax (order)
    push_mem(V_UNIT)                          # push unit
    call(0x43acb0)                            # push_front_inherit (ret 8)
    code.extend(b'\xa1' + struct.pack('<I', V_CODE))   # mov eax, [code]
    code.extend(b'\xc2\x0c\x00')             # ret 0xc
    return bytes(code)


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
        self.mu.mem_map(TABLE_HEAP, 0x10000)
        self.mu.mem_map(0x2f00000, 0x100000)
        self.write(GAME_POINTER, GAME)
        self.mu.mem_write(STOP, b'\xc3')
        self.mu.mem_write(STUB, b'\xc3')
        self.mu.mem_write(0x4b4f10, b'\xc3')
        self.mu.mem_write(0x4b4f20, b'\xc3')
        self.mu.mem_write(0x489800, b'\xc2\x04\x00')
        self.mu.mem_write(0x48a0f0, b'\xc2\x08\x00')
        self.mu.mem_write(THUNK, thunk_bytes())
        self.mu.hook_add(UC_HOOK_CODE, self.h_alloc, begin=0x4b4f10, end=0x4b4f10)
        self.mu.hook_add(UC_HOOK_CODE, self.h_free, begin=0x4b4f20, end=0x4b4f20)
        self.mu.hook_add(UC_HOOK_CODE, self.h_clear_weapons, begin=0x489800, end=0x489800)
        self.mu.hook_add(UC_HOOK_CODE, self.h_aim_reset, begin=0x48a0f0, end=0x48a0f0)
        self.mu.hook_add(UC_HOOK_CODE, self.h_stop_building, begin=0x43a227, end=0x43a227)
        self.mu.hook_add(UC_HOOK_CODE, self.h_destroy, begin=0x43a1f0, end=0x43a1f0)
        self.mu.hook_add(UC_HOOK_CODE, self.h_rand_result, begin=0x43b956, end=0x43b956)
        self.mu.hook_add(UC_HOOK_CODE, self.h_rand_result, begin=0x43bb38, end=0x43bb38)
        self.mu.hook_add(UC_HOOK_CODE, self.h_rand_entry, begin=0x4b6c30, end=0x4b6c30)
        self.mu.hook_add(UC_HOOK_CODE, self.h_handler, begin=STUB, end=STUB)
        self.table_mode = True
        self.heap = TABLE_HEAP
        self.ids = {}
        self.next_id = 1
        self.events = []
        self.action_source = None
        self.calls_this_op = 0
        self.rand_n = None

    # ----- memory helpers -----
    def read(self, address):
        return struct.unpack('<I', self.mu.mem_read(address, 4))[0]

    def read8(self, address):
        return self.mu.mem_read(address, 1)[0]

    def write(self, address, value):
        self.mu.mem_write(address, struct.pack('<I', value & 0xffffffff))

    def call(self, address, args, this=0):
        sp = STACK_TOP - (len(args) + 1) * 4
        self.write(sp, STOP)
        for i, value in enumerate(args):
            self.write(sp + 4 + i * 4, value)
        self.mu.reg_write(UC_X86_REG_ESP, sp)
        self.mu.reg_write(UC_X86_REG_ECX, this)
        self.mu.emu_start(address, STOP, count=20000000)
        if self.mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError(f'{address:#x} did not return')
        return self.mu.reg_read(UC_X86_REG_EAX)

    def arg(self, index):
        return self.read(self.mu.reg_read(UC_X86_REG_ESP) + 4 + 4 * index)

    def ret(self, value, pop):
        esp = self.mu.reg_read(UC_X86_REG_ESP)
        self.mu.reg_write(UC_X86_REG_EAX, value & 0xffffffff)
        self.mu.reg_write(UC_X86_REG_EIP, self.read(esp))
        self.mu.reg_write(UC_X86_REG_ESP, esp + 4 + pop)

    # ----- hooks -----
    def h_alloc(self, mu, address, size, data):
        count = self.arg(0)
        if self.table_mode:
            base = self.heap
            self.heap = (self.heap + count + 15) & ~7
        else:
            if count != ORDER_SIZE:
                raise AssertionError(f'unexpected allocation {count:#x}')
            base = self.heap
            self.heap += ORDER_SIZE + 2
            if self.heap >= HEAP_END:
                raise RuntimeError('oracle heap exhausted')
            self.ids[base] = self.next_id
            self.next_id += 1
        mu.mem_write(base, b'\xcd' * count)
        mu.reg_write(UC_X86_REG_EAX, base)

    def h_free(self, mu, address, size, data):
        if not self.table_mode:
            self.events.append(['free', self.ids[self.arg(0)]])

    def h_destroy(self, mu, address, size, data):
        order = mu.reg_read(UC_X86_REG_ECX)
        self.events.append(['destroy', self.ids[order], self.read(order + 0x42)])

    def h_clear_weapons(self, mu, address, size, data):
        self.events.append(['clear_weapons', self.unit_ref(mu.reg_read(UC_X86_REG_ECX)), self.arg(0)])

    def h_aim_reset(self, mu, address, size, data):
        self.events.append(['aim_reset', self.unit_ref(self.arg(0)), self.arg(1)])

    def h_stop_building(self, mu, address, size, data):
        order = mu.reg_read(UC_X86_REG_ESI)
        self.events.append(['stop_building', self.ids[order]])
        mu.reg_write(UC_X86_REG_EIP, 0x43a25d)

    def h_rand_entry(self, mu, address, size, data):
        self.rand_n = self.arg(0)

    def h_rand_result(self, mu, address, size, data):
        self.events.append(['rand', self.rand_n, mu.reg_read(UC_X86_REG_EAX)])

    def h_handler(self, mu, address, size, data):
        esp = mu.reg_read(UC_X86_REG_ESP)
        ret_address = self.read(esp)
        owner, order, ev = self.read(esp + 4), self.read(esp + 8), self.read(esp + 12)
        oid = self.ids[order]
        if ret_address == RET_DESTROY_CB:
            self.events.append(['destroy_cb', oid, self.unit_ref(owner), ev])
            self.ret(0, 12)
            return
        kind = {RET_MAIN: 'main', RET_BG: 'bg'}[ret_address]
        self.events.append(['call', kind, oid, self.unit_ref(owner), self.read8(order + 4), self.read8(order + 5), ev,
                            self.read(order + 0x4e), self.read(order + 0xa), self.read(order + 0x42)])
        action = self.action_source(kind)
        tick = self.read(TICK)
        self.write(order + 6, self.read(order + 6) | action['mask_or'])
        self.write(order + 0x4e, self.read(order + 0x4e) | action['pending_or'])
        self.write(order + 0x42, self.read(order + 0x42) | action['flags_or'])
        if action['wake'] is not None:
            self.write(order + 0xa, tick + action['wake'])
        push = action['push']
        if push is None:
            self.ret(action['code'], 12)
            return
        self.write(V_TYPE, push['type'])
        self.write(V_TARGET, self.target_address(push['target']))
        self.write(V_POS, self.pos_address(push['pos'], 3))
        self.write(V_P36, push['p36'])
        self.write(V_P3A, push['p3a'])
        self.write(V_CODE, action['code'])
        self.write(V_UNIT, UNIT)
        mu.reg_write(UC_X86_REG_EIP, THUNK)

    # ----- world image -----
    def unit_ref(self, address):
        if address == 0:
            return 0
        if address == UNIT:
            return 'unit'
        return (address - TARGETS) // UNIT_SIZE + 1

    def target_address(self, target):
        return 0 if target == 0 else TARGETS + (target - 1) * UNIT_SIZE

    def pos_address(self, pos, slot):
        if pos is None:
            return 0
        address = POS_SLOTS + slot * 12
        self.mu.mem_write(address, struct.pack('<iii', *pos))
        return address

    def build_table(self):
        for init in (0x403180, 0x406bf0, 0x415b20):
            self.call(init, [])
        begin, end = self.read(TABLE_BEGIN), self.read(TABLE_END)
        table = []
        for index in range((end - begin) // 0x19):
            e = begin + index * 0x19
            raw = bytes(self.mu.mem_read(e, 0x19))
            status_ptr, handler, draw, mask = struct.unpack_from('<IIII', raw, 0)
            icon = raw[0x10]
            flags, name_ptr = struct.unpack_from('<II', raw, 0x11)
            table.append(dict(id=index, name=self.cstr(name_ptr), status=self.cstr(status_ptr), handler=handler,
                              draw=draw, draw_mask=mask, icon=icon, flags=flags))
        for index in range(len(table)):
            self.write(begin + index * 0x19 + 4, STUB)
        self.table_mode = False
        return table

    def cstr(self, address):
        out = bytearray()
        while True:
            c = self.read8(address + len(out))
            if c == 0:
                return out.decode('latin1')
            out.append(c)

    def reset(self, setup):
        self.mu.mem_write(WORK, bytes(0x10000))
        self.heap = HEAP
        self.ids = {}
        self.next_id = 1
        self.write(TICK, setup['tick'])
        self.write(RNG_STATE, setup['seed'])
        self.write(PLAYER, setup['player_valid'])
        self.mu.mem_write(PLAYER + 0x73, bytes([setup['controller']]))
        self.mu.mem_write(DEF + 0x230, bytes([setup['default_mission']]))
        self.write(UNIT + 0x92, DEF)
        self.write(UNIT + 0x96, PLAYER)
        self.mu.mem_write(UNIT + 0xa6, struct.pack('<H', 1))
        self.mu.mem_write(UNIT + 0x6a, struct.pack('<iii', *setup['unit_pos']))
        for i in range(TARGET_COUNT):
            alive = 0 if i + 1 == TARGET_COUNT else 0x100 + i
            self.mu.mem_write(TARGETS + i * UNIT_SIZE + 0xa6, struct.pack('<H', alive))

    def order_list(self, head_offset):
        out = []
        order = self.read(UNIT + head_offset)
        guard = 0
        while order:
            m = self.mu.mem_read(order, ORDER_SIZE)
            if struct.unpack_from('<I', m, 0x1e)[0] != order:
                raise AssertionError('order self reference broken')
            x, y, z = struct.unpack_from('<iii', m, 0x22)
            out.append([self.ids[order], m[4], m[5], struct.unpack_from('<I', m, 6)[0], struct.unpack_from('<I', m, 0xa)[0],
                        self.unit_ref(struct.unpack_from('<I', m, 0xe)[0]), self.unit_ref(struct.unpack_from('<I', m, 0x16)[0]),
                        x, y, z, struct.unpack_from('<I', m, 0x2e)[0], struct.unpack_from('<I', m, 0x32)[0],
                        struct.unpack_from('<i', m, 0x36)[0], struct.unpack_from('<i', m, 0x3a)[0], struct.unpack_from('<i', m, 0x3e)[0],
                        struct.unpack_from('<I', m, 0x42)[0], struct.unpack_from('<I', m, 0x46)[0],
                        struct.unpack_from('<I', m, 0x4e)[0], struct.unpack_from('<I', m, 0x52)[0]])
            order = struct.unpack_from('<I', m, 0x4a)[0]
            guard += 1
            if guard > 4000:
                raise AssertionError('cyclic order list')
        return out

    def target_refs(self):
        """Number of live reference objects linked on each target's +0xa2 chain."""
        counts = []
        for i in range(TARGET_COUNT):
            n, ref = 0, self.read(TARGETS + i * UNIT_SIZE + 0xa2)
            while ref:
                n += 1
                ref = self.read(ref + 8)
            counts.append(n)
        return counts

    def address_of(self, oid):
        for address, value in self.ids.items():
            if value == oid:
                return address
        raise KeyError(oid)

    def construct(self, spec):
        base = self.heap
        self.heap += ORDER_SIZE + 2
        self.ids[base] = self.next_id
        self.next_id += 1
        self.call(0x43a0c0, [spec['type'], self.target_address(spec['target']), self.pos_address(spec['pos'], 0),
                             spec['p36'], spec['p3a'], spec['p3e']], this=base)
        return base


# ----- random scenario generation -----
class Generator:
    def __init__(self, rng, table):
        self.rng = rng
        self.table = table

    def type_id(self, queued):
        r = self.rng.random()
        if queued and r < 0.25:
            return self.rng.choice(queued)[1]
        if r < 0.75:
            return self.rng.choice(INTERESTING_TYPES)
        return self.rng.randrange(len(self.table))

    def target(self):
        r = self.rng.random()
        if r < 0.45:
            return 0
        if r < 0.55:
            return TARGET_COUNT
        return self.rng.randint(1, TARGET_COUNT - 1)

    def pos(self, anchors, queued):
        rng = self.rng
        r = rng.random()
        if r < 0.15:
            return None
        if queued and r < 0.5:
            o = rng.choice(queued)
            base = [o[7], o[8], o[9]]
        elif r < 0.58:
            base = [0, 0, 0]
        elif r < 0.63:
            base = [rng.choice([0x7ff80000, -0x7ff80000, 0x7fffffff, -0x80000000]), 0, rng.choice([0x7ff80000, -0x7ff80000, 0])]
        else:
            base = list(rng.choice(anchors))
        jitter = lambda: rng.choice([0, 0x100000, -0x100000, 0x100001, -0x100001, 0xfffff, -0xfffff,
                                     rng.randint(-0x300000, 0x300000), rng.randint(-0x80000, 0x80000)])
        return [s32(base[0] + jitter()), s32(base[1] + rng.randint(-0x40000, 0x40000)), s32(base[2] + jitter())]

    def small(self):
        return self.rng.choice([0, 0, 1, 2, 3, -1, 5, self.rng.randint(-10, 10), self.rng.randint(-0x8000, 0x8000)])

    def action(self, calls, kind):
        rng = self.rng
        if calls >= 2 * FORCE_AFTER:
            return dict(code=7 if kind == 'main' else 6, mask_or=0, pending_or=0, flags_or=0, wake=None, push=None)
        if calls >= FORCE_AFTER:
            return dict(code=3, mask_or=0, pending_or=0, flags_or=0, wake=None, push=None)
        code = rng.choices([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0x7fffffff],
                           [8, 8, 10, 10, 6, 14, 5, 3, 5, 6, 1, 1, 1])[0]
        mask_or = rng.choices([0, 1, 2, 3, 0x20, 0xe0, 0x10000, 0x10001, 0x12, 0x800], [30, 15, 8, 6, 6, 5, 5, 4, 4, 2])[0]
        pending_or = rng.choices([0, 1, 0x20, 0x10000, 0x40, 2], [70, 8, 8, 6, 4, 4])[0]
        flags_or = rng.choices([0, 0x4000, 0x400000, 0x4, 0x1000, 0x10000, 0x800000], [70, 8, 6, 5, 5, 4, 2])[0]
        wake = rng.choice([None, None, None, 0, 1, 15, 30, 60, rng.randint(0, 90), -5])
        push = None
        if rng.random() < 0.08:
            push = dict(type=self.type_id([]), target=self.target(), pos=self.pos([[0x400000, 0, 0x400000]], []),
                        p36=self.small(), p3a=self.small())
        return dict(code=code, mask_or=mask_or, pending_or=pending_or, flags_or=flags_or, wake=wake, push=push)


def run_sequence(native, table, rng, index):
    gen = Generator(rng, table)
    tick = rng.choice([rng.randint(0, 5000), rng.randint(0, 5000), 0xffffffc0 + rng.randint(0, 40), 0x7fffffe0])
    setup = dict(tick=tick, seed=rng.randint(1, 0xfffffffe), player_valid=rng.choice([1, 1, 1, 0]),
                 controller=rng.choice([0, 1, 1, 2, 2, 3]),
                 default_mission=rng.choice([0, 0x28, 0x28, 0x29, 0x25, 0x3f, 0x15, 0x2c]),
                 unit_pos=[rng.randint(-0x200000, 0x2000000), rng.randint(0, 0x800000), rng.randint(-0x200000, 0x2000000)])
    native.reset(setup)
    anchors = [[rng.randint(0, 0x4000000), rng.randint(0, 0x1000000), rng.randint(0, 0x4000000)] for _ in range(4)]
    anchors.append([0x100000, 0, 0x100000])
    ops = []
    count = rng.randint(20, 90)
    for _ in range(count):
        main = native.order_list(0x5c)
        bg = native.order_list(0x60)
        queued = main + bg
        r = rng.random()
        op = {}
        ids_before = native.next_id
        native.events = []
        native.calls_this_op = 0
        actions = []

        def source(kind):
            a = gen.action(native.calls_this_op, kind)
            native.calls_this_op += 1
            actions.append(a)
            return a

        native.action_source = source
        result = None
        if r < 0.22 or r < 0.44:
            name = 'insert' if r < 0.22 else 'issue'
            shift = rng.choice([0, 1, 1]) if name == 'issue' else rng.choice([0, 1])
            args = dict(type=gen.type_id(queued), shift=shift, target=gen.target(), pos=gen.pos(anchors, queued),
                        p36=gen.small(), p3a=gen.small())
            if name == 'issue' and queued and rng.random() < 0.4:
                o = rng.choice(main or queued)
                args['type'] = o[1]
                args['target'] = rng.choice([0, o[6], o[6], gen.target()])
            native.call(0x43adc0 if name == 'insert' else 0x43afc0,
                        [args['type'], args['shift'], UNIT, native.target_address(args['target']),
                         native.pos_address(args['pos'], 1), args['p36'], args['p3a']])
            op = dict(op=name, **args)
        elif r < 0.62:
            advance = rng.choice([0, 0, 1, 15, 30, 31, 45, rng.randint(0, 80)])
            native.write(TICK, native.read(TICK) + advance)
            op = dict(op='dispatch', advance=advance)
            native.call(0x43b7c0, [UNIT])
        elif r < 0.72:
            advance = rng.choice([0, 1, 30, rng.randint(0, 80)])
            native.write(TICK, native.read(TICK) + advance)
            op = dict(op='dispatch_bg', advance=advance)
            native.call(0x43bad0, [UNIT])
        elif r < 0.78:
            if queued and rng.random() < 0.6:
                o = rng.choice(queued)
                bits = rng.choice([1, 2, 0x20, 0x40, 0x80, 0x10, 0x8, 0x10000, 0x800, 0x21])
                native.write(native.address_of(o[0]) + 0x4e, native.read(native.address_of(o[0]) + 0x4e) | bits)
                op = dict(op='post_order', id=o[0], bits=bits)
            else:
                bits = rng.choice([1, 2, 0x20, 0x40, 0x80, 0x10, 0x8, 0x800, 0x8021])
                value = (struct.unpack('<H', native.mu.mem_read(UNIT + 0xba, 2))[0] | bits) & 0xffff
                native.mu.mem_write(UNIT + 0xba, struct.pack('<H', value))
                op = dict(op='post_unit', bits=bits)
        elif r < 0.81 and queued:
            o = rng.choice(queued)
            op = dict(op='remove', id=o[0])
            native.call(0x439f80, [UNIT, native.address_of(o[0])])
        elif r < 0.83:
            include = rng.choice([0, 0, 1])
            op = dict(op='clear', include_bg=include)
            native.call(0x439eb0, [UNIT, include])
        elif r < 0.85 and main:
            o = rng.choice(main)
            op = dict(op='rotate', id=o[0])
            native.call(0x439fe0, [UNIT, native.address_of(o[0])])
        elif r < 0.88 and queued:
            o = rng.choice(queued)
            op = dict(op='patrol_append', id=o[0])
            native.call(0x43a020, [UNIT, native.address_of(o[0])])
        elif r < 0.92:
            args = dict(type=gen.type_id(queued), p36=rng.choice([0, 1, 2, 3]),
                        count=rng.choice([1, 2, 5, -1, -2, -5, 0, -100]))
            op = dict(op='factory', **args)
            native.call(0x43b0b0, [args['type'], UNIT, args['p36'], args['count']])
        elif r < 0.94:
            t = gen.type_id(queued)
            op = dict(op='find', type=t)
            found = native.call(0x439e30, [UNIT, t])
            result = native.ids[found] if found else 0
        elif r < 0.95:
            p36 = rng.choice([0, 1, 2, 3])
            op = dict(op='count', p36=p36)
            result = s32(native.call(0x439d80, [UNIT, p36]))
        else:
            spec = dict(type=gen.type_id(queued), target=gen.target(), pos=gen.pos(anchors, queued), p36=gen.small(),
                        p3a=gen.small(), p3e=gen.small())
            which = rng.choice(['push_front_inherit', 'append', 'marker_insert'])
            op = dict(op=which, spec=spec)
            order = native.construct(spec)
            native.call({'push_front_inherit': 0x43acb0, 'append': 0x43ad10, 'marker_insert': 0x43ad50}[which], [UNIT, order])
        op['actions'] = actions
        op['allocated'] = native.next_id - ids_before
        op['events'] = native.events
        op['result'] = result
        op['tick'] = native.read(TICK)
        op['unit_ev'] = struct.unpack('<H', native.mu.mem_read(UNIT + 0xba, 2))[0]
        op['main'] = native.order_list(0x5c)
        op['bg'] = native.order_list(0x60)
        op['target_refs'] = native.target_refs()
        ops.append(op)
    return dict(index=index, setup=setup, ops=ops)


def static_table(executable):
    info = inspect_pe(executable)

    def off(va):
        rva = va - 0x400000
        for s in info['sections']:
            if s['rva'] <= rva < s['rva'] + max(s['raw_size'], s['virtual_size']):
                return s['raw_offset'] + rva - s['rva']
        raise KeyError(hex(va))

    def u32(va):
        return struct.unpack_from('<I', executable, off(va))[0]

    def cstr(va):
        o = off(va)
        return executable[o:executable.index(b'\0', o)].decode('latin1')

    entries = []
    for base, count in ((0x4fc490, 0x17), (0x4fc6e8, 0x16), (0x4fca18, 0x16)):
        for i in range(count):
            e = base + i * 0x19
            entries.append(dict(name=cstr(u32(e + 0x15)), status=cstr(u32(e)), handler=u32(e + 4), draw=u32(e + 8),
                                draw_mask=u32(e + 0xc), icon=executable[off(e + 0x10)], flags=u32(e + 0x11), source=e))
    entries.sort(key=lambda x: bytes(c + 32 if 65 <= c <= 90 else c for c in x['name'].encode('latin1')))
    return entries


def main():
    executable = Path('local/original/TotalA.exe').read_bytes()
    native = Native(executable)
    table = native.build_table()
    static = static_table(executable)
    mismatches = [i for i, (a, b) in enumerate(zip(table, static))
                  if any(a[k] != b[k] for k in ('name', 'status', 'handler', 'draw', 'draw_mask', 'icon', 'flags'))]
    if len(table) != 67 or len(static) != 67 or mismatches:
        raise AssertionError(f'native table ({len(table)}) differs from static parse at {mismatches}')
    for entry, s in zip(table, static):
        entry['source'] = s['source']
    folder = Path('local/orders')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'order-table.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, builder='0x403180/0x406bf0/0x415b20 -> 0x43bc90',
                                                             entries=table), indent=1), encoding='utf-8')
    rng = random.Random(0x43adc0)
    sequences = []
    for index in range(int(sys.argv[1]) if len(sys.argv) > 1 else 1500):
        sequences.append(run_sequence(native, table, rng, index))
    (folder / 'native-order-queue.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, sequences=sequences)), encoding='utf-8')
    op_counts, code_counts, event_counts = {}, {}, {}
    max_main = max_bg = 0
    for sequence in sequences:
        for op in sequence['ops']:
            op_counts[op['op']] = op_counts.get(op['op'], 0) + 1
            for a in op['actions']:
                code_counts[str(a['code'])] = code_counts.get(str(a['code']), 0) + 1
            for e in op['events']:
                key = e[0] if e[0] != 'call' else 'call.' + e[1]
                event_counts[key] = event_counts.get(key, 0) + 1
            max_main = max(max_main, len(op['main']))
            max_bg = max(max_bg, len(op['bg']))
    coverage = dict(toggle_removals=0, head_idle_strips=0, marker_mid_inserts=0, destroys_with_0x10000=0, destroys_without_0x10000=0,
                    idle_orders_created=0, code9_timer_branch=0, code9_remove_branch=0, background_flag_orders_in_main=0,
                    wrap_sequences=sum(1 for s in sequences if s['setup']['tick'] >= 0xffffff00), dead_target_orders=0,
                    protected_survivors=0)
    for sequence in sequences:
        previous_ids = set()
        for op in sequence['ops']:
            events = op['events']
            if op['op'] == 'issue' and op['shift'] and op['allocated'] == 0 and any(e[0] == 'destroy' for e in events):
                coverage['toggle_removals'] += 1
            if op['op'] in ('insert', 'issue'):
                coverage['head_idle_strips'] += sum(1 for e in events if e[0] == 'destroy' and e[2] & 0x4000)
                new = [o for o in op['main'] if o[0] not in previous_ids]
                if new and op['main'][-1][0] != new[0][0]:
                    coverage['marker_mid_inserts'] += 1
                if not op['shift'] and any(o[15] & 4 for o in op['main'] if o[0] in previous_ids):
                    coverage['protected_survivors'] += 1
            for e in events:
                if e[0] == 'destroy':
                    coverage['destroys_with_0x10000' if e[2] & 0x10000 else 'destroys_without_0x10000'] += 1
            if op['op'] == 'dispatch':
                pushes = sum(1 for a in op['actions'] if a['push'])
                coverage['idle_orders_created'] += max(0, op['allocated'] - pushes)
                codes = [a['code'] for a in op['actions']]
                coverage['code9_timer_branch'] += sum(1 for e in events if e[0] == 'rand' and e[1] == 30)
                coverage['code9_remove_branch'] += max(0, codes.count(9) - sum(1 for e in events if e[0] == 'rand' and e[1] == 30))
            if any(o[15] & 0x40000 for o in op['main']):
                coverage['background_flag_orders_in_main'] += 1
            coverage['dead_target_orders'] += sum(1 for o in op['main'] + op['bg'] if o[15] & 0x200 and o[6] == 0)
            previous_ids = {o[0] for o in op['main'] + op['bg']}
    table_summary = [dict(id=e['id'], name=e['name'], handler=hex(e['handler']), draw=hex(e['draw']), draw_mask=e['draw_mask'],
                          icon=e['icon'], flags=hex(e['flags'])) for e in table]
    summary = dict(exe_sha256=EXE_HASH, oracle='tools/native_order_queue.py', comparator='godot/compare_native_order_queue.gd',
                   trace='local/orders/native-order-queue.json and local/orders/order-table.json (git-ignored)',
                   order_table=dict(entries=len(table), static_parse_matches_native_build=True, table=table_summary),
                   sequences=len(sequences), operations=sum(op_counts.values()), operations_by_kind=op_counts,
                   handler_codes=code_counts, events=event_counts, coverage=coverage, max_main_length=max_main, max_bg_length=max_bg,
                   stubs={'0x4b4f10': 'operator new -> bump allocator, sequential order ids',
                          '0x4b4f20': 'operator delete -> no-op, records freed order id',
                          'table +4 handlers': 'redirected after the table dump to one scripted stub (records call; ORs mask/pending/flags, '
                                               'optional wake=tick+d, optional ORIGINAL 0x43a0c0+0x43acb0 push via x86 thunk, returns code)',
                          '0x43a227..0x43a25d': 'StopBuilding COB call + 0x456190 skipped, recorded',
                          '0x489800': 'clear weapon targets, recorded only',
                          '0x48a0f0': 'aim reset, recorded only',
                          'unit+0': 'movement object null -> destroy goal cancel block not taken (goal stays 0)'},
                   unmodified=['0x43a0c0', '0x4895c0', '0x489690', '0x489650', '0x43a1f0 (except StopBuilding block)', '0x43adc0',
                               '0x43afc0', '0x43b7c0', '0x43bad0', '0x439f80', '0x439eb0', '0x439fe0', '0x43a020', '0x439e30',
                               '0x439d80', '0x43b0b0', '0x43ac60', '0x43acb0', '0x43ad10', '0x43ad50', '0x4b6c30',
                               '0x403180/0x406bf0/0x415b20/0x43bc90 table build and sort'],
                   scope=('One owner unit; 6 target units (id 6 dead, +0xa6 == 0); ticks from 0, mid-range, near 0x7fffffff and '
                          'near 0xffffffff (unsigned wake compare, u32 wrap); controller byte 0-3, player[0] zero/non-zero, '
                          'default mission types incl. a background type; positions from anchors, queued orders (toggle hits), '
                          'the origin, +-0x100000 edges and int32 wrap-around; all 67 types with bias to flag-rich types. '
                          f'Handler stubs force code 3 after {FORCE_AFTER} calls in one operation and code 7/6 after {2 * FORCE_AFTER} (tick-wrap livelock). '
                          'Excluded: handler bodies, group issue 0x48cf30, cursor selector 0x43f0e0, save/load 0x43a420/0x43a970, '
                          'goal objects, unit-death reference notification, 0x43ac60 with a non-head successor.'))
    Path('analysis/native-order-queue-validation.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(f'NATIVE_ORDER_QUEUE table {len(table)} entries; {len(sequences)} sequences / {summary["operations"]} operations; '
          f'{op_counts}; events {event_counts}; max main {max_main} bg {max_bg}')


if __name__ == '__main__':
    main()
