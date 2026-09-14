"""Execute the original LOS height-grid builder 0x482c20 (the map loader calls it at 0x483cec) in Unicorn.

The whole routine runs unmodified. Its only calls are to the operator new/delete wrappers, listed with tadis.py
0x482c20 0x483210:
  0x482c29 call 0x4b4f10 (new 10 bytes, object stored at game+0x142b7)
  0x482ca9 call 0x4b4f20 (delete old overlay grid [game+0x1429f])
  0x482cc5 call 0x4b4f10 (new overlay grid of 10-byte cells)
  0x482f48 call 0x4b4f20 (delete old LOS height grid [game+0x1428f])
  0x482f62 call 0x4b4f10 (new LOS height grid, pad*2 bytes)
0x4b4f10 and 0x4b4f20 only forward to CRT malloc 0x4d8660 / free 0x4d8670 (cdecl, caller pops). They are replaced by
a bump allocator that fills each block with random garbage, to show that nothing depends on fresh memory being zero,
and by a no-op free. The first half of the routine (0x482c27..0x482f15) builds the 8x8-cell overlay grid at
game+0x1429f from game+0x14223/0x14227 and cell byte +5. It runs natively, but only the LOS height grid at
game+0x1428f {ptr, w2, h2, pad} is recorded.

Inputs: game+0x14233 map width, game+0x14237 map height (16-px cells), game+0x14287 pointer to 13-byte cells with the
height at +4, and game+0x1427f sea level.
"""
import base64
import hashlib
import json
from pathlib import Path
import random
import struct

from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH, STOP, STACK_TOP, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX

CELLS = 0x2000000
HEAP = 0x3000000
HEAP_SIZE = 0x1000000
MAPS = ['greenhaven', 'hundred-isles', 'lava-run', 'biggie-biggs']


class HeightGridOracle:
    def __init__(self):
        self.native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
        mu = self.native.mu
        mu.mem_map(CELLS, 0x1000000)
        mu.mem_map(HEAP, HEAP_SIZE)
        mu.mem_write(0x4b4f10, b'\xc3')
        mu.mem_write(0x4b4f20, b'\xc3')
        mu.hook_add(UC_HOOK_CODE, self.allocate, begin=0x4b4f10, end=0x4b4f10)
        self.freed = []
        mu.hook_add(UC_HOOK_CODE, self.free, begin=0x4b4f20, end=0x4b4f20)
        self.rng = random.Random(0x482c20)
        self.heap = HEAP
        self.allocations = []

    def allocate(self, mu, address, size, data):
        count = self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        if self.heap + count > HEAP + HEAP_SIZE:
            raise MemoryError('oracle heap exhausted')
        block = self.heap
        mu.mem_write(block, self.rng.randbytes(count))
        self.heap = (self.heap + count + 15) & ~15
        self.allocations.append(count)
        mu.reg_write(UC_X86_REG_EAX, block)

    def free(self, mu, address, size, data):
        self.freed.append(self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4))

    def run(self, width, height, sea_level, heights):
        native, mu = self.native, self.native.mu
        count = width * height
        assert len(heights) == count and count * 13 <= 0x1000000
        cells = bytearray(self.rng.randbytes(count * 13))
        cells[4::13] = heights
        mu.mem_write(CELLS, bytes(cells))
        native.write(GAME + 0x14233, width)
        native.write(GAME + 0x14237, height)
        native.write(GAME + 0x14223, width * 16)
        native.write(GAME + 0x14227, height * 16)
        native.write(GAME + 0x14287, CELLS)
        mu.mem_write(GAME + 0x1427f, bytes([sea_level]))
        # Stale pointers are only passed to delete; sizes are rewritten before use.
        for base in (0x1428f, 0x1429f):
            mu.mem_write(GAME + base, struct.pack('<IIII', 0xdead0000 | base & 0xffff, 0x7777, 0x8888, 0x9999))
        self.heap, self.allocations, self.freed = HEAP, [], []
        sp = STACK_TOP - 4
        native.write(sp, STOP)
        mu.reg_write(UC_X86_REG_ESP, sp)
        mu.emu_start(0x482c20, STOP)
        if mu.reg_read(UC_X86_REG_EIP) != STOP or mu.reg_read(UC_X86_REG_ESP) != sp + 4:
            raise RuntimeError('0x482c20 did not return')
        pointer, w2, h2, pad = struct.unpack('<IiiI', mu.mem_read(GAME + 0x1428f, 16))
        grid = bytes(mu.mem_read(pointer, pad * 2)) if pad else b''
        if not pad and pointer != 0:
            raise AssertionError('empty grid should store a null pointer')
        return dict(w2=w2, h2=h2, pad=pad, null_pointer=pointer == 0, grid=base64.b64encode(grid).decode(),
                    grid_sha256=hashlib.sha256(grid).hexdigest(), allocations=list(self.allocations), freed=len(self.freed))


def random_heights(rng, count, style):
    if style == 'zero':
        return bytes(count)
    if style == 'full':
        return bytes([255]) * count
    if style == 'low':
        return bytes(rng.choice([0, 0, 0, 1, 2, 3, 5, 7]) for _ in range(count))
    if style == 'high':
        return bytes(rng.choice([255, 255, 254, 253, 250, 248]) for _ in range(count))
    if style == 'bimodal':
        return bytes(rng.choice([rng.randrange(0, 8), rng.randrange(248, 256)]) for _ in range(count))
    if style == 'constant':
        return bytes([rng.randrange(256)]) * count
    return bytes(rng.randrange(256) for _ in range(count))


def random_cases(oracle):
    rng = random.Random(20260914)
    styles = ['zero', 'full', 'low', 'high', 'bimodal', 'constant', 'random', 'random']
    seas = [0, 40, 255, None]
    cases = []
    shapes = [(w, h) for w in (1, 2, 3) for h in (1, 2, 3)]
    shapes += [(w, h) for w in (1, 2, 3, 4, 5) for h in (4, 5, 16, 17, 33)]
    shapes += [(w, h) for w in (16, 17, 32, 33) for h in (1, 2, 3)]
    while len(shapes) < 240:
        roll = rng.random()
        limit = 12 if roll < 0.4 else 48 if roll < 0.9 else 130
        shapes.append((rng.randrange(1, limit), rng.randrange(1, limit)))
    for index, (width, height) in enumerate(shapes):
        style = styles[index % len(styles)]
        sea = seas[(index // len(styles)) % len(seas)]
        if sea is None:
            sea = rng.randrange(256)
        heights = random_heights(rng, width * height, style)
        native = oracle.run(width, height, sea, heights)
        cases.append(dict(kind='random', label=f'{style}-{index}', width=width, height=height, sea_level=sea,
                          heights=base64.b64encode(heights).decode(), native=native))
    return cases


def map_cases(oracle):
    cases = []
    for key in MAPS:
        folder = Path('local/maps') / key
        scene = json.loads((folder / 'scene.json').read_text(encoding='utf-8'))
        heights = (folder / 'heights.bin').read_bytes()
        width, height = scene['height_grid_width'], scene['height_grid_height']
        native = oracle.run(width, height, scene['sea_level'], heights)
        cases.append(dict(kind='map', label=key, map=key, width=width, height=height, sea_level=scene['sea_level'],
                          heights_sha256=hashlib.sha256(heights).hexdigest(), native=native))
        print('MAP', key, width, height, scene['sea_level'], native['w2'], native['h2'], native['pad'], flush=True)
    return cases


def main():
    oracle = HeightGridOracle()
    maps = map_cases(oracle)
    randoms = random_cases(oracle)
    folder = Path('local/visibility')
    folder.mkdir(parents=True, exist_ok=True)
    stubs = {'0x4b4f10': 'operator new wrapper (-> malloc 0x4d8660): bump allocator filled with random bytes',
             '0x4b4f20': 'operator delete wrapper (-> free 0x4d8670): no-op'}
    (folder / 'native-los-heights.json').write_text(json.dumps(dict(
        version=1, exe_sha256=EXE_HASH, routine='0x482c20', call_site='0x483cec', stubs=stubs,
        cases=maps + randoms)), encoding='utf-8')
    print(f'NATIVE_LOS_HEIGHTS {len(maps)} maps, {len(randoms)} random grids')


if __name__ == '__main__':
    main()
