"""Original screen-to-world cursor projection 0x484b50 (with the 0x485070 height sampler).

Runs the routine unmodified on random and cliff-heavy height grids, random sea levels and map pixel sizes, including
points outside the map (clamped by the routine). Writes local/cursor/native-screen-to-world.json.
"""
import json
from pathlib import Path
import random
from native_movement_reference import MovementReference, GAME
from cob import signed

GRID = 0x2000000
OUT = 0x2100000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(GRID, 0x200000)
    rng = random.Random(0x484b50)
    scenes = []
    for scene in range(240):
        cells_w, cells_h = rng.randrange(2, 64), rng.randrange(2, 64)
        style = scene % 4
        heights = []
        for index in range(cells_w * cells_h):
            if style == 0:
                heights.append(rng.randrange(256))
            elif style == 1:
                heights.append(rng.choice([0, 255, rng.randrange(256)]))
            elif style == 2:
                heights.append(min(255, (index % cells_w) * rng.randrange(0, 24)))
            else:
                heights.append(min(255, (index // cells_w) * rng.randrange(0, 40)))
        sea = rng.choice([0, 0, rng.randrange(256), 255, 40])
        map_w = cells_w * 16 - rng.choice([0, 0, rng.randrange(40)])
        map_h = cells_h * 16 - rng.choice([0, 0, rng.randrange(40)])
        map_w, map_h = max(1, map_w), max(1, map_h)
        grid = bytearray(cells_w * cells_h * 13)
        for i, value in enumerate(heights):
            grid[i * 13 + 4] = value
        native.mu.mem_write(GRID, bytes(grid))
        native.write(GAME + 0x14223, map_w)
        native.write(GAME + 0x14227, map_h)
        native.write(GAME + 0x14233, cells_w)
        native.write(GAME + 0x14237, cells_h)
        native.write(GAME + 0x14287, GRID)
        native.mu.mem_write(GAME + 0x1427f, bytes([sea]))
        calls = []
        for _ in range(60):
            sx = rng.choice([rng.randrange(map_w), rng.randrange(-60, map_w + 60), 0, map_w - 1])
            sy = rng.choice([rng.randrange(map_h), rng.randrange(-60, map_h + 60), 0, map_h - 1, rng.randrange(max(1, map_h - 20), map_h)])
            native.call(0x484b50, [sx & 0xffffffff, sy & 0xffffffff, OUT])
            calls.append([sx, sy] + [signed(native.read(OUT + 4 * axis)) for axis in range(3)])
        scenes.append(dict(cells_w=cells_w, cells_h=cells_h, map_w=map_w, map_h=map_h, sea=sea, heights=heights, calls=calls))
    output = Path('local/cursor')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'native-screen-to-world.json').write_text(json.dumps(dict(scenes=scenes)), encoding='utf-8')
    print('NATIVE_SCREEN_TO_WORLD %d calls in %d scenes' % (sum(len(s['calls']) for s in scenes), len(scenes)))


if __name__ == '__main__':
    main()
