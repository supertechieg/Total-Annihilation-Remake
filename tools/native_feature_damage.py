"""Original terrain height sampler 0x485070 and the splash feature pass of 0x49a120 with 0x4244b0 damage.

The splash routine runs unmodified from entry until its feature/unit cell loop ends (0x49a664). Unit slots
are empty. Feature replacement 0x423550 and ignition 0x4233a0 are replaced by recorders; 0x4244b0 runs
natively and its entries are recorded.
"""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME, DEFINITION
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
from native_cob_reference import EXE_HASH, UC_HOOK_CODE, STACK_TOP
from cob import signed

GRID, PROJECTILE, POSITION, NETWORK = 0x1009000, 0x100b000, 0x100b100, 0x100b200
FEATURES, INSTANCES = 0x1010000, 0x1011000
SIZE = 12
SPLASH_END = 0x49a664
RETURN = 0x100b300


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    calls = dict(hits=[], replaced=[], ignited=[])

    def recorder(name, count):
        def hook(mu, address, size, data):
            sp = mu.reg_read(UC_X86_REG_ESP)
            calls[name].append([signed(native.read(sp + 4 + 4 * i)) for i in range(count)])
        return hook

    for address, name in [(0x423550, 'replaced'), (0x4233a0, 'ignited')]:
        native.mu.mem_write(address, b'\xc2\x0c\x00')
        native.mu.hook_add(UC_HOOK_CODE, recorder(name, 3), begin=address, end=address)
    native.mu.hook_add(UC_HOOK_CODE, recorder('hits', 3), begin=0x4244b0, end=0x4244b0)
    native.write(GAME + 0x14233, SIZE)
    native.write(GAME + 0x14237, SIZE)
    native.write(GAME + 0x14287, GRID)
    native.write(GAME + 0x1426f, FEATURES)
    native.write(GAME + 0x1420b, INSTANCES)
    native.write(GAME + 0x391e9, NETWORK)
    native.write(NETWORK, 0)
    native.mu.mem_write(RETURN, b'\xc3')
    rng = random.Random(0x4244b0)

    heights_cases = []
    for index in range(1000):
        heights = [rng.randrange(256) for _ in range(SIZE * SIZE)]
        grid = bytearray(SIZE * SIZE * 13)
        for i, value in enumerate(heights):
            grid[i * 13 + 4] = value
        native.mu.mem_write(GRID, bytes(grid))
        x = rng.randrange(-40 * 65536, (SIZE * 16 + 40) * 65536)
        z = rng.randrange(-40 * 65536, (SIZE * 16 + 40) * 65536)
        for axis, value in enumerate([x, 0, z]):
            native.write(POSITION + 4 * axis, value)
        result = signed(native.call(0x485070, [POSITION]))
        heights_cases.append(dict(heights=heights, x=x, z=z, result=result))

    splash_cases = []
    for index in range(1500):
        heights = [rng.randrange(256) for _ in range(SIZE * SIZE)]
        codes = [0xffff] * (SIZE * SIZE)
        words = [0] * (SIZE * SIZE)
        bits = [0] * (SIZE * SIZE)
        definitions = []
        for _ in range(4):
            flags = rng.choice([0, 0, 0, 0x200, 0x10, 0x1, 0x11, 0x40])
            definitions.append(dict(footprintx=rng.randrange(1, 4), footprintz=rng.randrange(1, 4),
                                    damage=rng.choice([0, rng.randrange(1, 60), rng.randrange(60, 3000), 0xffff]), flags=flags))
        instances = []
        for _ in range(rng.randrange(1, 7)):
            code = rng.randrange(4)
            definition = definitions[code]
            x, z = rng.randrange(SIZE - definition['footprintx'] + 1), rng.randrange(SIZE - definition['footprintz'] + 1)
            cells = [(z + dz) * SIZE + x + dx for dz in range(definition['footprintz']) for dx in range(definition['footprintx'])]
            if any(codes[cell] != 0xffff for cell in cells):
                continue
            anchor = z * SIZE + x
            codes[anchor] = code
            if rng.randrange(3):
                words[anchor] = len(instances)
                bits[anchor] = 1 | (rng.randrange(16) << 3)
                instances.append(dict(position=[(x * 16 + rng.randrange(-8, 40)) * 65536 + rng.randrange(65536),
                                                rng.randrange(-20, 280) * 65536 + rng.randrange(65536),
                                                (z * 16 + rng.randrange(-8, 40)) * 65536 + rng.randrange(65536)],
                                      damage=rng.choice([0, rng.randrange(65536)]),
                                      x=x if rng.randrange(12) else x + 1, z=z))
            else:
                words[anchor] = rng.choice([0, rng.randrange(200), rng.randrange(65536)])
                bits[anchor] = rng.randrange(16) << 3
            for dz in range(definition['footprintz']):
                for dx in range(definition['footprintx']):
                    if dx or dz:
                        cell = (z + dz) * SIZE + x + dx
                        codes[cell] = 0xfffe
                        words[cell] = dz | (dx << 8)
                        bits[cell] = rng.randrange(2) * 0x80
        weapon = dict(default=rng.choice([0, rng.randrange(1, 100), rng.randrange(100, 70000)]) & 0xffff,
                      area=rng.choice([0, 8, 16, rng.randrange(1, 120), rng.randrange(40, 160), rng.randrange(120, 400)]),
                      firestarter=rng.choice([0, 0, rng.randrange(1, 256)]), flags=rng.choice([0, 0, 0, 0x4000, 0x80000]))
        game_flags = rng.choice([8, 8, 8, 0, 0xc])
        position = [rng.randrange(-40, SIZE * 16 + 40) * 65536 + rng.randrange(65536), rng.randrange(-20, 300) * 65536,
                    rng.randrange(-40, SIZE * 16 + 40) * 65536 + rng.randrange(65536)]
        if index % 3 != 2 and instances:
            target = rng.choice(instances)['position']
            position = [target[0] + rng.randrange(-40, 40) * 65536, target[1] + rng.randrange(-20, 20) * 65536, target[2] + rng.randrange(-40, 40) * 65536]
        grid = bytearray(SIZE * SIZE * 13)
        for i in range(SIZE * SIZE):
            grid[i * 13 + 4] = heights[i]
            grid[i * 13 + 8:i * 13 + 10] = codes[i].to_bytes(2, 'little')
            grid[i * 13 + 10:i * 13 + 12] = words[i].to_bytes(2, 'little')
            grid[i * 13 + 12] = bits[i]
        native.mu.mem_write(GRID, bytes(grid))
        native.mu.mem_write(FEATURES, bytes(0x400))
        for i, definition in enumerate(definitions):
            base = FEATURES + i * 0x100
            native.mu.mem_write(base + 0x94, struct.pack('<hh', definition['footprintx'], definition['footprintz']))
            native.mu.mem_write(base + 0xea, struct.pack('<H', definition['damage']))
            native.mu.mem_write(base + 0xfe, struct.pack('<H', definition['flags']))
        native.mu.mem_write(INSTANCES, bytes(48 * 8))
        for i, instance in enumerate(instances):
            base = INSTANCES + i * 48
            for axis, value in enumerate(instance['position']):
                native.write(base + 8 + 4 * axis, value)
            native.mu.mem_write(base + 0x26, struct.pack('<Hhh', instance['damage'], instance['x'], instance['z']))
        native.mu.mem_write(GAME + 0x37f2f, bytes([game_flags]))
        native.mu.mem_write(DEFINITION + 0xd4, struct.pack('<HH', weapon['default'], weapon['area']))
        native.mu.mem_write(DEFINITION + 0x10b, bytes([weapon['firestarter']]))
        native.write(DEFINITION + 0x111, weapon['flags'])
        native.mu.mem_write(PROJECTILE, bytes(0x80))
        native.write(PROJECTILE, DEFINITION)
        for axis, value in enumerate(position):
            native.write(POSITION + 4 * axis, value)
        for key in calls:
            calls[key].clear()
        sp = STACK_TOP - 12
        native.write(sp, RETURN)
        native.write(sp + 4, PROJECTILE)
        native.write(sp + 8, POSITION)
        native.mu.reg_write(UC_X86_REG_ESP, sp)
        native.mu.emu_start(0x49a120, SPLASH_END, timeout=5000000, count=5000000)
        if native.mu.reg_read(UC_X86_REG_EIP) != SPLASH_END:
            raise RuntimeError(f'Splash case {index} stopped at {native.mu.reg_read(UC_X86_REG_EIP):#x}')
        final_words = [struct.unpack_from('<H', native.mu.mem_read(GRID + i * 13 + 10, 2))[0] for i in range(SIZE * SIZE)]
        final_damage = [struct.unpack_from('<H', native.mu.mem_read(INSTANCES + i * 48 + 0x26, 2))[0] for i in range(len(instances))]
        splash_cases.append(dict(heights=heights, codes=codes, words=words, bits=bits, definitions=definitions, instances=instances,
                                 weapon=weapon, game_flags=game_flags, position=position,
                                 hits=[[(call[0] - GRID) // 13, call[1], call[2]] for call in calls['hits']],
                                 replaced=[call[:2] for call in calls['replaced']], ignited=[call[:2] for call in calls['ignited']],
                                 replace_params=[call[2] for call in calls['replaced']], final_words=final_words, final_damage=final_damage))
    folder = Path('local/features')
    folder.mkdir(exist_ok=True)
    (folder / 'native-feature-damage.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, size=SIZE, heights=heights_cases, splash=splash_cases)))
    hit_cases = sum(1 for case in splash_cases if case['hits'])
    print(f'NATIVE_FEATURE_DAMAGE {len(heights_cases)} height cases, {len(splash_cases)} splash cases ({hit_cases} with hits, '
          f'{sum(len(case["replaced"]) for case in splash_cases)} replacements, {sum(len(case["ignited"]) for case in splash_cases)} ignitions)')


if __name__ == '__main__':
    main()
