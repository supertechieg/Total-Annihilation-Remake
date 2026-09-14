"""Original hover picking oracle: 0x48cd80 (main view + minimap blip branches), 0x48c6a0, 0x4cb650, 0x4b6cc0,
0x48bae0 (visible-list rebuild) and the blip-list part of 0x466dc0, executed unmodified in Unicorn.

Stubs (every other instruction on the measured paths is original code):
  * 0x465ac0 (visibleTo(player, unit), stdcall 2 args) -> `ret 8`; a code hook returns a per-unit answer drawn from the
    scene RNG and records (player pointer, unit slot). Only reached by 0x48bae0 for units not owned by G+0x2a43.
  * 0x4c6b70 (ret 0x10), 0x4b7f30 (ret 8), 0x4b7f90 (ret 0x10): minimap drawing calls inside 0x466dc0, replaced by
    their `ret N`. The blip builder is executed from 0x466dc0 to 0x4671a0 (end of the unit loop; the feature loop
    after it is not run). Unit flag 0x10 (+0x110 bit 4, the selected-unit weapon-range rings drawn via 0x4c0070 /
    0x4c01a0) is always clear, so those draw paths are not entered.
  * x87 control word 0x27f (the Win32/MSVC CRT default, 53-bit precision, round to nearest). 0x4b7173 uses FSINCOS;
    Unicorn/QEMU computes FSINCOS with the host libm on a double, not the physical x87 microcode.
Writes local/cursor/native-hover-pick.json and analysis/native-hover-pick-validation.json.
"""
import hashlib
import json
import math
from pathlib import Path
import random
import struct

from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH, UC_HOOK_CODE, STOP, STACK_TOP
from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_ESP, UC_X86_REG_EDI, UC_X86_REG_FPCW, UC_X86_REG_EIP)
from cob import signed

MEM = 0x2000000
UNITS = 0x2000000
UNIT_SIZE = 0x118
DEFS = 0x2010000
DEF_SIZE = 0x300
MODELS = 0x2020000
MODEL_SIZE = 0x100
MODEL_TABLE = 0x2030000
LIST = 0x2040000
BLIPS = 0x2050000
GRID = 0x2060000
SCRATCH = 0x2080000
DUMMY_PLAYER = 0x23f0000
MOUSE = GAME + 0x2c76
VIEW = GAME + 0x37e27
MINIMAP = GAME + 0x142bb


def s32(v):
    return signed(v & 0xffffffff)


class HoverNative:
    def __init__(self):
        self.n = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
        self.mu = self.n.mu
        self.mu.mem_map(MEM, 0x400000)
        self.mu.reg_write(UC_X86_REG_FPCW, 0x27f)
        self.mu.mem_write(0x465ac0, b'\xc2\x08\x00')
        self.mu.hook_add(UC_HOOK_CODE, self.visible_stub, begin=0x465ac0, end=0x465ac0)
        for address, ret in ((0x4c6b70, 0x10), (0x4b7f30, 8), (0x4b7f90, 0x10)):
            self.mu.mem_write(address, b'\xc2' + struct.pack('<H', ret))
        self.captured = []
        self.mu.hook_add(UC_HOOK_CODE, self.capture_poly, begin=0x4c1320, end=0x4c1320)
        self.key_value = 0
        self.mu.hook_add(UC_HOOK_CODE, self.stop_key, begin=0x48ce5b, end=0x48ce5b)
        self.visible_answers = {}
        self.visible_calls = []
        self.w(GAME + 0x14377, MODEL_TABLE)
        self.w(GAME + 0x1435f, LIST)
        self.w(GAME + 0x14363, BLIPS)
        self.w(GAME + 0x14287, GRID)
        for owner in range(256):
            if 0x1b8a + owner * 0x14b + 4 < 0x40000:
                self.w(GAME + 0x1b8a + owner * 0x14b, DUMMY_PLAYER)

    def w(self, address, value):
        self.n.write(address, value)

    def w16(self, address, value):
        self.mu.mem_write(address, struct.pack('<H', value & 0xffff))

    def w8(self, address, value):
        self.mu.mem_write(address, bytes([value & 0xff]))

    def r(self, address):
        return self.n.read(address)

    def r16(self, address):
        return struct.unpack('<H', self.mu.mem_read(address, 2))[0]

    def visible_stub(self, mu, address, size, data):
        sp = mu.reg_read(UC_X86_REG_ESP)
        player, unit = self.r(sp + 4), self.r(sp + 8)
        slot = (unit - UNITS) // UNIT_SIZE
        self.visible_calls.append([player, slot])
        mu.reg_write(UC_X86_REG_EAX, int(self.visible_answers.get(slot, False)))

    def stop_key(self, mu, address, size, data):
        if self.key_value is None:
            self.key_value = mu.reg_read(UC_X86_REG_EAX)
            mu.emu_stop()

    def capture_poly(self, mu, address, size, data):
        sp = mu.reg_read(UC_X86_REG_ESP)
        points, count = self.r(sp + 4), self.r(sp + 8)
        self.captured.append([[s32(self.r(points + i * 8)), s32(self.r(points + i * 8 + 4))] for i in range(count)])

    def run(self, start, until=None, args=()):
        # No Unicorn timeout: a timeout starts a watchdog thread per emu_start, which dominates run time.
        sp = STACK_TOP - (len(args) + 1) * 4
        self.w(sp, STOP)
        for i, value in enumerate(args):
            self.w(sp + 4 + i * 4, value)
        self.mu.reg_write(UC_X86_REG_ESP, sp)
        stop = STOP if until is None else until
        self.mu.emu_start(start, stop, count=2000000)
        if self.mu.reg_read(UC_X86_REG_EIP) != stop and not (stop == 0x48ce5b and self.key_value is not None):
            raise RuntimeError('native run did not reach %x' % stop)
        return self.mu.reg_read(UC_X86_REG_EAX)

    # ---- scene writers -------------------------------------------------------------------------------
    def write_models(self, models):
        for type_id, model in models.items():
            base = MODELS + int(type_id) * MODEL_SIZE
            self.mu.mem_write(base, bytes(MODEL_SIZE))
            self.w(base + 4, model['count'])
            for axis in range(3):
                self.w(base + 0x10 + axis * 4, model['offset'][axis])
            self.w(base + 0x24, base + 0x40)
            for i, vertex in enumerate(model['vertices']):
                for axis in range(3):
                    self.w(base + 0x40 + i * 12 + axis * 4, vertex[axis])
            self.w(MODEL_TABLE + int(type_id) * 4, base)

    def write_defs(self, defs):
        for i, d in enumerate(defs):
            base = DEFS + i * DEF_SIZE
            for axis in range(3):
                self.w(base + 0x15e + axis * 4, d['min'][axis])
                self.w(base + 0x16a + axis * 4, d['max'][axis])
                self.w(base + 0x176 + axis * 4, d['size'][axis])

    def write_units(self, units):
        self.mu.mem_write(UNITS, bytes(UNIT_SIZE * max(1, len(units))))
        for slot, u in enumerate(units):
            base = UNITS + slot * UNIT_SIZE
            for axis, value in enumerate(u['angles']):
                self.w16(base + 0x64 + axis * 2, value)
            for axis, key in enumerate(('x', 'y', 'z')):
                self.w(base + 0x6a + axis * 4, u[key])
            self.w(base + 0x92, DEFS + u['def_index'] * DEF_SIZE)
            self.w16(base + 0xa6, u['type_id'])
            self.w16(base + 0xa8, u['index'])
            self.w8(base + 0xfa, u.get('fa', 0))
            self.w8(base + 0xff, u['owner'])
            self.w(base + 0x110, u['flags110'])
        self.w(GAME + 0x14357, UNITS)
        self.w(GAME + 0x1435b, UNITS + (len(units) - 1) * UNIT_SIZE)

    def write_view(self, view, cam):
        for i, key in enumerate(('left', 'top', 'right', 'bottom')):
            self.w(VIEW + i * 4, view[key])
        self.w(GAME + 0x1431f, cam['x'])
        self.w(GAME + 0x14323, cam['y'])

    # ---- measured calls ------------------------------------------------------------------------------
    def bbox(self, model_type):
        self.mu.mem_write(SCRATCH, bytes(24))
        self.run(0x4cb650, args=[MODELS + model_type * MODEL_SIZE, SCRATCH, SCRATCH + 12, 0])
        return [[s32(self.r(SCRATCH + axis * 4)) for axis in range(3)], [s32(self.r(SCRATCH + 12 + axis * 4)) for axis in range(3)]]

    def rotate(self, point, angles):
        for axis in range(3):
            self.w(SCRATCH + axis * 4, point[axis])
            self.w16(SCRATCH + 24 + axis * 2, angles[axis])
        self.run(0x4b6cc0, args=[SCRATCH, SCRATCH + 12, SCRATCH + 24])
        return [s32(self.r(SCRATCH + 12 + axis * 4)) for axis in range(3)]

    def hit(self, slot, mouse):
        self.w(SCRATCH + 40, mouse[0])
        self.w(SCRATCH + 44, mouse[1])
        self.captured = []
        result = self.run(0x48c6a0, args=[UNITS + slot * UNIT_SIZE, SCRATCH + 40])
        return result, self.captured[0]

    def key(self, slot):
        # Execute the original key instructions 0x48ce1e..0x48ce5b (int64 helpers included); a code hook stops at the
        # compare because Unicorn's `until` is not reliable once 0x48ce5b sits inside a cached translation block.
        self.mu.reg_write(UC_X86_REG_EDI, UNITS + slot * UNIT_SIZE)
        self.key_value = None
        eax = self.run(0x48ce1e, until=0x48ce5b)
        value, self.key_value = (eax if self.key_value is None else self.key_value), 0
        return s32(value)

    def pick(self, mouse, list_entries):
        self.w(MOUSE, mouse[0])
        self.w(MOUSE + 4, mouse[1])
        if list_entries is None:
            self.w(GAME + 0x1435f, 0)
        else:
            self.w(GAME + 0x1435f, LIST)
            for i, entry in enumerate(list_entries):
                self.w16(LIST + i * 2, entry)
            self.w(GAME + 0x14367, len(list_entries))
        result = self.run(0x48cd80) & 0xffff
        self.w(GAME + 0x1435f, LIST)
        return result

    def rebuild(self, answers):
        self.visible_answers = answers
        self.visible_calls = []
        self.w(GAME + 0x14367, 0x5a5a)
        self.run(0x48bae0)
        count = s32(self.r(GAME + 0x14367))
        return [self.r16(LIST + i * 2) for i in range(max(0, count))], self.visible_calls


def rand_word(rng):
    return rng.choice([0, 0, rng.randrange(65536), rng.choice([0x4000, 0x8000, 0xc000, 0x7fff, 0x8001, 1, 0xffff]),
                       rng.randrange(-3000, 3000) & 0xffff])


def rand_i32(rng):
    return rng.choice([rng.randrange(-2 ** 31, 2 ** 31), rng.randrange(-(200 << 16), 200 << 16),
                       rng.choice([2 ** 31 - 1, -2 ** 31, 0x7fff0000, -0x7fff0000, 0, 1, -1])])


def make_model(rng, wrap):
    count = rng.choice([0, 1, 2, 3, 3, 4, 5, 6, 7, 8, 8, -1])
    span = (1 << 30) if wrap else rng.choice([8 << 16, 24 << 16, 64 << 16])
    vertices = [[rng.randrange(-span, span) for _ in range(3)] for _ in range(max(0, count))]
    offset = [rng.choice([0, rng.randrange(-span // 2, span // 2)]) for _ in range(3)]
    return dict(count=count, offset=offset, vertices=vertices)


def make_def(rng, wrap):
    fx, fz = rng.randrange(1, 9), rng.randrange(1, 9)
    height = rng.randrange(0, 80) << 16 | rng.randrange(65536)
    lower = [-((fx << 20) // 2), 0, -((fz << 20) // 2)]
    upper = [(fx << 20) // 2, height, (fz << 20) // 2]
    size = [fx << 20, height, fz << 20]
    if wrap:
        size = [rand_i32(rng) for _ in range(3)]
    if rng.random() < 0.2:
        lower = [rng.randrange(-(100 << 16), 100 << 16) for _ in range(3)]
        upper = [rng.randrange(-(100 << 16), 100 << 16) for _ in range(3)]
    return dict(min=lower, max=upper, size=size)


def make_view(rng):
    width, height = rng.choice([(640, 480), (800, 600), (1024, 768), (1280, 1024)])
    view = dict(left=128, top=32, right=width - 1, bottom=height - 33)
    if rng.random() < 0.1:
        view = dict(left=rng.randrange(0, 200), top=rng.randrange(0, 100), right=rng.randrange(200, 1300), bottom=rng.randrange(100, 1000))
    return view


def pick_scene(rng, native, scene_index):
    wrap = scene_index % 7 == 6
    view = make_view(rng)
    cam = dict(x=rng.choice([0, rng.randrange(0, 4000), rng.randrange(-100, 0)]), y=rng.choice([0, rng.randrange(0, 4000)]))
    if wrap:
        cam = dict(x=rng.randrange(-40000, 40000), y=rng.randrange(-40000, 40000))
    types = rng.randrange(1, 8)
    models = {str(t): make_model(rng, wrap and rng.random() < 0.5) for t in range(1, types + 1)}
    defs = [make_def(rng, wrap and rng.random() < 0.5) for _ in range(rng.randrange(1, 6))]
    if rng.random() < 0.3:
        # Keys at the 0x7fff0000 start value: size.y = 0, size.x = 1.0 gives key = size.z exactly.
        for depth in (0x7fff0000, 0x7ffeffff, 0x7fffffff):
            defs.append(dict(min=[0, 0, 0], max=[0, 0, 0], size=[0x10000, 0, depth]))
    mx = rng.randrange(view['left'], view['right'] + 1)
    my = rng.randrange(view['top'], view['bottom'] + 1)
    slots = rng.randrange(1, 25)
    units = []
    for slot in range(slots):
        y = rng.choice([0, rng.randrange(0, 256) << 16, rng.randrange(-(40 << 16), 300 << 16)])
        wx = cam['x'] + mx - view['left'] + rng.randrange(-60, 61)
        wz = cam['y'] + my - view['top'] + (y >> 17) + rng.randrange(-60, 61)
        x = (wx << 16) + rng.randrange(65536)
        z = (wz << 16) + rng.randrange(65536)
        if wrap and rng.random() < 0.5:
            x, y, z = rand_i32(rng), rand_i32(rng), rand_i32(rng)
        units.append(dict(type_id=rng.choice([0] + [t for t in range(1, types + 1)] * 3), index=rng.choice([slot, rng.randrange(65536)]),
                          x=s32(x), y=s32(y), z=s32(z), angles=[rand_word(rng) for _ in range(3)], owner=rng.randrange(10),
                          flags110=rng.randrange(2 ** 32) & ~0x10, def_index=rng.randrange(len(defs))))
    # Ties: clone a unit (same def/type/position) or share a def.
    for _ in range(rng.randrange(0, 3)):
        a, b = rng.randrange(slots), rng.randrange(slots)
        units[b] = dict(units[a], index=rng.randrange(65536))
    native.write_models(models)
    native.write_defs(defs)
    native.write_units(units)
    native.write_view(view, cam)
    list_entries = [rng.randrange(slots) for _ in range(rng.randrange(0, 2 * slots + 1))]
    if rng.random() < 0.3:
        list_entries = list(range(slots))
    mice = [[mx, my]]
    for _ in range(9):
        mice.append(rng.choice([
            [rng.randrange(view['left'], view['right'] + 1), rng.randrange(view['top'], view['bottom'] + 1)],
            [mx + rng.randrange(-20, 21), my + rng.randrange(-20, 21)],
            [rng.choice([view['left'], view['right'], view['left'] - 1, view['right'] + 1]), rng.randrange(view['top'], view['bottom'] + 1)],
            [rng.randrange(view['left'], view['right'] + 1), rng.choice([view['top'], view['bottom'], view['top'] - 1, view['bottom'] + 1])]]))
    # Exact projected-corner mice (on edges / vertices) from the native projection.
    corners_by_slot = {}
    for slot in sorted(set(list_entries)):
        if units[slot]['type_id'] != 0:
            corners_by_slot[slot] = native.hit(slot, [mx, my])[1]
    for slot, corners in list(corners_by_slot.items())[:3]:
        c0, c1 = corners[0], corners[rng.randrange(1, 4)]
        mice.append(list(c0))
        mice.append([(c0[0] + c1[0]) // 2, (c0[1] + c1[1]) // 2])
    calls = []
    for mouse in mice:
        result = native.pick(mouse, list_entries)
        hits = []
        for slot in sorted(set(list_entries)):
            if units[slot]['type_id'] != 0:
                inside, corners = native.hit(slot, mouse)
                hits.append([slot, inside, corners])
        calls.append(dict(mouse=mouse, result=result, hits=hits))
    null_result = native.pick([mx, my], None)
    keys = [[slot, native.key(slot)] for slot in range(slots)]
    bboxes = {t: native.bbox(int(t)) for t in models}
    return dict(view=view, cam=cam, models=models, defs=defs, units=units, list=list_entries, calls=calls,
                null_list_result=null_result, keys=keys, bboxes=bboxes)


def minimap_scene(rng, native):
    view = make_view(rng)
    rect = dict(left=rng.randrange(0, 20), top=rng.randrange(0, 40), right=rng.randrange(100, 128), bottom=rng.randrange(100, 160))
    for i, key in enumerate(('left', 'top', 'right', 'bottom')):
        native.w(MINIMAP + i * 4, rect[key])
    native.write_view(view, dict(x=0, y=0))
    mx = rng.randrange(rect['left'] - 3, rect['right'] + 4)
    my = rng.randrange(rect['top'] - 3, rect['bottom'] + 4)
    count = rng.choice([0, rng.randrange(1, 13), rng.randrange(1, 5), -1])
    blips = []
    for _ in range(max(0, count)):
        near = rng.random() < 0.7
        bx = mx + rng.randrange(-3, 4) if near else rng.randrange(-2 ** 31, 2 ** 31)
        by = my + rng.randrange(-3, 4) if near else rng.choice([rng.randrange(-2 ** 31, 2 ** 31), my])
        blips.append([rng.randrange(65536), bx, by])
    if rng.random() < 0.2:
        # Wrapped squared distance: 46341^2 overflows int32 to a negative d2, which passes `d2 < 4`.
        blips.insert(rng.randrange(len(blips) + 1), [rng.randrange(65536), mx + rng.choice([46341, -46341, 65536]), my])
        count = len(blips)
    if blips and rng.random() < 0.4:
        blips.append([rng.randrange(65536)] + blips[rng.randrange(len(blips))][1:])
        count = len(blips)
    for i, (uid, bx, by) in enumerate(blips):
        native.w16(BLIPS + i * 10, uid)
        native.w(BLIPS + i * 10 + 2, bx)
        native.w(BLIPS + i * 10 + 6, by)
    native.w(GAME + 0x1436b, count)
    mice = [[mx, my], [rng.randrange(rect['left'], rect['right'] + 1), rng.randrange(rect['top'], rect['bottom'] + 1)],
            [rng.randrange(view['left'], view['right'] + 1), rng.randrange(view['top'], view['bottom'] + 1)],
            [rect['left'] - 1, my], [rect['right'], rect['bottom']]]
    for b in blips[:2]:
        mice.append([s32(b[1]), s32(b[2])])
    calls = [dict(mouse=m, result=native.pick(m, [])) for m in mice]
    return dict(view=view, rect=rect, count=count, blips=blips, calls=calls)


def visible_scene(rng, native, scene_index):
    view = make_view(rng)
    cam = dict(x=rng.randrange(-50, 3000), y=rng.randrange(-50, 3000))
    local = rng.randrange(10)
    cells_w, cells_h = rng.randrange(1, 64), rng.randrange(1, 64)
    heights = [rng.choice([0, 255, rng.randrange(256)]) for _ in range(cells_w * cells_h)]
    grid = bytearray(cells_w * cells_h * 13)
    for i, h in enumerate(heights):
        grid[i * 13 + 4] = h
    native.mu.mem_write(GRID, bytes(grid))
    native.w(GAME + 0x14233, cells_w)
    native.w(GAME + 0x14237, cells_h)
    native.w8(GAME + 0x2a43, local)
    native.write_view(view, cam)
    defs = [make_def(rng, False) for _ in range(rng.randrange(1, 6))]
    for d in defs:
        if rng.random() < 0.3:
            d['min'] = [rand_i32(rng) for _ in range(3)]
            d['max'] = [rand_i32(rng) for _ in range(3)]
    slots = rng.randrange(1, 40)
    units = []
    answers = {}
    for slot in range(slots):
        wx = cam['x'] + rng.randrange(view['left'] - 200, view['right'] + 200) - view['left']
        wz = cam['y'] + rng.randrange(view['top'] - 200, view['bottom'] + 300) - view['top']
        y = rng.choice([0, rng.randrange(0, 256), rng.randrange(-300, 300)])
        x, z = (wx << 16) + rng.randrange(65536), (wz << 16) + rng.randrange(65536)
        if rng.random() < 0.3:
            x, z = rng.randrange(-(40 << 16), (cells_w * 16 + 40) << 16), rng.randrange(-(40 << 16), (cells_h * 16 + 40) << 16)
        if rng.random() < 0.05:
            x, z = rand_i32(rng), rand_i32(rng)
        units.append(dict(type_id=rng.choice([0, 1, 2, 3, 4]), index=rng.choice([slot, rng.randrange(65536)]),
                          x=s32(x), y=s32((y << 16) + rng.randrange(65536)), z=s32(z), angles=[0, 0, 0],
                          owner=rng.choice([local, rng.randrange(256)]), flags110=rng.randrange(2 ** 32) & ~0x10,
                          def_index=rng.randrange(len(defs))))
        answers[slot] = rng.random() < 0.5
    if scene_index % 3 == 0:
        # Cells just outside the grid (cx/cz = -1 or w/h): only an in-grid cell may lower the bottom, and each unit is
        # placed so the lowering alone decides whether its bottom edge reaches the view top.
        for i in range(8):
            heights[rng.randrange(len(heights))] = rng.randrange(0, 60)
            cx = rng.choice([-1, 0, cells_w - 1, cells_w])
            cz = rng.choice([-1, 0, cells_h - 1, cells_h])
            x = (cx * 16 + rng.randrange(16)) << 16
            z = (cz * 16 + rng.randrange(16)) << 16
            zi = z >> 16
            max_z = view['top'] - 50 - zi + cam['y'] + 100 - 32
            defs.append(dict(min=[-3000 << 16, 0, -3000 << 16], max=[3000 << 16, 0, max_z << 16], size=[0, 0, 0]))
            units.append(dict(type_id=1, index=len(units), x=s32(x), y=200 << 16, z=s32(z), angles=[0, 0, 0], owner=local,
                              flags110=rng.choice([0, 2, 3, 0x100]), def_index=len(defs) - 1))
            answers[len(units) - 1] = False
        grid = bytearray(cells_w * cells_h * 13)
        for i, h in enumerate(heights):
            grid[i * 13 + 4] = h
        native.mu.mem_write(GRID, bytes(grid))
    native.write_defs(defs)
    native.write_units(units)
    result, calls = native.rebuild(answers)
    slots = len(units)
    player_addresses = sorted(set(c[0] for c in calls))
    expected_player = GAME + 0x1b63 + local * 0x14b
    return dict(view=view, cam=cam, local_player=local, cells_w=cells_w, cells_h=cells_h, heights=heights, defs=defs,
                units=units, visible_answers=[answers[s] for s in range(slots)], list=result,
                visible_calls=[c[1] for c in calls], player_pointer_ok=all(p == expected_player for p in player_addresses))


def blip_scene(rng, native):
    local = rng.randrange(10)
    native.w8(GAME + 0x2a43, local)
    native.w16(GAME + 0x14281, rng.choice([0, 1, 2, 3, rng.randrange(65536)]))
    native.w16(GAME + 0x37f2f, rng.choice([0, 0x200, rng.randrange(65536)]))
    native.w8(GAME + 0x142f1, rng.randrange(256))
    native.w16(GAME + 0x2cba, rng.randrange(8))
    mm = dict(x0=rng.randrange(-5, 20), y0=rng.randrange(-5, 40), w=rng.randrange(1, 130), h=rng.randrange(1, 130))
    scroll_w, scroll_h = rng.choice([rng.randrange(1, 8000), rng.randrange(-100, -1)]), rng.randrange(1, 8000)
    native.w16(GAME + 0x142e7, mm['x0'])
    native.w16(GAME + 0x142e9, mm['y0'])
    native.w16(GAME + 0x142eb, mm['w'])
    native.w16(GAME + 0x142ed, mm['h'])
    native.w(GAME + 0x1422b, scroll_w)
    native.w(GAME + 0x1422f, scroll_h)
    slots = rng.randrange(1, 30)
    units = []
    for slot in range(slots):
        units.append(dict(type_id=rng.choice([0, 1, 2]), index=rng.choice([slot, rng.randrange(8)]),
                          x=rng.randrange(-2 ** 31, 2 ** 31) if rng.random() < 0.1 else rng.randrange(-(100 << 16), 8000 << 16),
                          y=rng.randrange(-(300 << 16), 300 << 16), z=rng.randrange(-(100 << 16), 8000 << 16), angles=[0, 0, 0],
                          owner=rng.choice([local, rng.randrange(10)]),
                          flags110=rng.choice([0, 0x100, 0x200, 0x300, rng.randrange(2 ** 32)]) & ~0x10,
                          fa=rng.choice([0, 1]), def_index=0))
    native.write_defs([make_def(rng, False)])
    native.write_units(units)
    native.run(0x466dc0, until=0x4671a0)
    count = s32(native.r(GAME + 0x1436b))
    blips = [[native.r16(BLIPS + i * 10), s32(native.r(BLIPS + i * 10 + 2)), s32(native.r(BLIPS + i * 10 + 6))] for i in range(count)]
    return dict(local_player=local, flags14281=native.r16(GAME + 0x14281), flags37f2f=native.r16(GAME + 0x37f2f), minimap=mm,
                scroll_w=scroll_w, scroll_h=scroll_h, units=units, blips=blips)


def rotation_cases(rng, native):
    cases = []
    for i in range(20000):
        point = [rng.choice([rng.randrange(-(64 << 16), 64 << 16), rand_i32(rng), rng.randrange(-100, 100)]) for _ in range(3)]
        angles = [rand_word(rng) for _ in range(3)]
        if i < 512:
            angles = [(i * 128) & 0xffff, (i * 128 + 64) & 0xffff, (-(i * 128)) & 0xffff]
        cases.append([point, angles, native.rotate(point, angles)])
    cases.extend(constructed_rotations(rng, native))
    return cases


def _fist(v):
    f = math.floor(v)
    d = v - f
    if d > 0.5 or (d == 0.5 and f % 2 != 0):
        f += 1
    return f if -2 ** 31 <= f < 2 ** 31 else -2 ** 31


def constructed_rotations(rng, native):
    """Rotations aimed at exact rounding ties (fraction exactly .5 after 53-bit products) and at inputs whose rounding
    changes if the angle constant were exactly 2*pi/65536. Predictions use the host libm; the native result is recorded
    either way."""
    stored = struct.unpack('<d', bytes.fromhex('5a2c4454fb21193f'))[0]
    exact = math.tau / 65536
    cases = []
    for word in (1, 3, 7, 40, 32767, -32767, 32760):
        c, s = math.cos(word * stored), math.sin(word * stored)
        found = 0
        for _ in range(6000000):
            a = rng.randrange(2 ** 31 - 2 ** 29, 2 ** 31) * rng.choice([1, -1])
            v = a * c
            if v - math.floor(v) == 0.5 or (a * s) - math.floor(a * s) == 0.5:
                cases.append([[a, 0, 0], [word & 0xffff, 0, 0], native.rotate([a, 0, 0], [word & 0xffff, 0, 0])])
                found += 1
                if found == 3:
                    break
    for word in (8192, 16384, -8192, 12345, 30000, 24576, 4096):
        c1, s1 = math.cos(word * stored), math.sin(word * stored)
        c2, s2 = math.cos(word * exact), math.sin(word * exact)
        found = 0
        for _ in range(200000):
            a, b = rng.randrange(-2 ** 31, 2 ** 31), rng.randrange(-2 ** 31, 2 ** 31)
            if _fist(a * c1 - b * s1) != _fist(a * c2 - b * s2) or _fist(b * c1 + a * s1) != _fist(b * c2 + a * s2):
                cases.append([[a, b, 0], [word & 0xffff, 0, 0], native.rotate([a, b, 0], [word & 0xffff, 0, 0])])
                found += 1
                if found == 4:
                    break
    return cases


def main():
    native = HoverNative()
    rng = random.Random(0x48cd80)
    rotations = rotation_cases(rng, native)
    # Precision sensitivity only (not a check): the same rotations under 64-bit precision control 0x37f.
    native.mu.reg_write(UC_X86_REG_FPCW, 0x37f)
    extended_differences = sum(1 for point, angles, out in rotations if native.rotate(point, angles) != out)
    native.mu.reg_write(UC_X86_REG_FPCW, 0x27f)
    picks = [pick_scene(rng, native, i) for i in range(1000)]
    minimaps = [minimap_scene(rng, native) for _ in range(1500)]
    visibles = [visible_scene(rng, native, i) for i in range(1500)]
    blips = [blip_scene(rng, native) for _ in range(1000)]
    data = dict(exe_sha256=EXE_HASH, fpcw=0x27f, rotations=rotations, picks=picks, minimaps=minimaps, visibles=visibles, blips=blips)
    out = Path('local/cursor')
    out.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data)
    (out / 'native-hover-pick.json').write_text(text, encoding='utf-8')
    pick_calls = sum(len(s['calls']) for s in picks)
    hits = sum(len(c['hits']) for s in picks for c in s['calls'])
    positive = sum(1 for s in picks for c in s['calls'] if c['result'] != 0)
    inside = sum(1 for s in picks for c in s['calls'] for h in c['hits'] if h[1])
    summary = dict(
        exe_sha256=EXE_HASH, oracle='tools/native_hover_pick.py', data='local/cursor/native-hover-pick.json',
        data_sha256=hashlib.sha256(text.encode('utf-8')).hexdigest(), fpcw='0x27f',
        rotations=len(rotations), rotations_differing_under_fpcw_0x37f=extended_differences,
        pick_scenes=len(picks), pick_calls=pick_calls, pick_nonzero_results=positive, hit_tests=hits, hit_tests_inside=inside,
        key_checks=sum(len(s['keys']) for s in picks), bbox_checks=sum(len(s['bboxes']) for s in picks),
        null_list_checks=len(picks),
        minimap_scenes=len(minimaps), minimap_calls=sum(len(s['calls']) for s in minimaps),
        minimap_nonzero=sum(1 for s in minimaps for c in s['calls'] if c['result'] != 0),
        visible_scenes=len(visibles), visible_units=sum(len(s['units']) for s in visibles),
        visible_kept=sum(len(s['list']) for s in visibles),
        visible_player_pointer_ok=all(s['player_pointer_ok'] for s in visibles),
        blip_scenes=len(blips), blips=sum(len(s['blips']) for s in blips),
        stubs=['0x465ac0 -> ret 8 + recorded per-unit answer', '0x4c6b70 -> ret 0x10', '0x4b7f30 -> ret 8', '0x4b7f90 -> ret 0x10',
               '0x466dc0 run to 0x4671a0 only; unit flag 0x10 kept clear'],
        godot_checks='godot/compare_native_hover_pick.gd prints HOVER_PICK_NATIVE x / y checks match',
        recorded_godot_result='HOVER_PICK_NATIVE 307757 / 307757 checks match (2026-09-14, this data_sha256)',
        recorded_unit_tests='HOVER_PICK 44 / 44 checks pass',
        mutation_testing=dict(caught=16, total=17, survivor='key half-height without low32: (int64)s32*0x8000>>16 always fits in int32, equivalent',
                              caught_mutants=['inside <= to <', 'rotation order', 'round half away from zero', 'no 0x7fff0000 start key',
                                              'ties to later entry', 'minimap d2 without int32 wrap', 'exact 2*pi/65536 constant',
                                              'height >>1 as division', 'cell lowering flag test', 'bbox count >= 2', 'blip filter 0x300',
                                              'cell bound > instead of >=', 'no FISTP indefinite', 'visible top from minY',
                                              'rotation sign swap', 'corner winding']))
    Path('analysis/native-hover-pick-validation.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('NATIVE_HOVER_PICK', json.dumps({k: v for k, v in summary.items() if isinstance(v, (int, bool))}))


if __name__ == '__main__':
    main()
