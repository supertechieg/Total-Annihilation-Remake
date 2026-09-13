"""Record isolated original x86 speed/vector and movement-animation behavior.

The speed routine runs unmodified. The animation routine's script invocation
boundary is replaced by a recorder; pathfinding, collisions and terrain sampling
are outside this oracle. Requires the same local dependencies as the COB oracle.
"""
import argparse
import itertools
import json
import math
from pathlib import Path
import random
import struct

from native_cob_reference import NativeReference, EXE_HASH, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EAX, UC_X86_REG_FPCW, UC_X86_REG_FPSW, UC_X86_REG_FPTAG
from cob import signed

MOTION = 0x1004000
UNIT = 0x1005000
DEFINITION = 0x1006000
GAME = 0x1400000


class MovementReference(NativeReference):
    def __init__(self, executable, cob):
        super().__init__(executable, cob)
        # Unicorn defaults do not represent FINIT: initialize an empty x87 stack
        # and masked exceptions before entering the original floating-point CRT.
        self.mu.reg_write(UC_X86_REG_FPCW, 0x37f)
        self.mu.reg_write(UC_X86_REG_FPSW, 0)
        self.mu.reg_write(UC_X86_REG_FPTAG, 0xffff)
        self.mu.mem_map(GAME, 0x40000)
        self.write(0x511de8, GAME)
        self.write(UNIT + 0x92, DEFINITION)
        self.callbacks = []
        # Record names at the script invocation boundary; stdcall/thiscall ret 12.
        self.mu.mem_write(0x4b0940, b'\xc2\x0c\x00')
        self.mu.hook_add(UC_HOOK_CODE, self.record_callback, begin=0x4b0940, end=0x4b0940)
        actual = struct.unpack('<512h', self.mu.mem_read(0x509f00, 1024))
        expected = tuple(round(math.sin(i * math.tau / 512) * 8192) for i in range(512))
        if actual != expected:
            raise AssertionError('Regenerated trigonometric table differs')
        self.sine = actual
        self.waypoints = []
        self.write(MOTION, 0x100c000)
        self.write(0x100c000, 0x100d000)
        self.write(0x100d014, 0x100e000)
        self.write(0x100d00c, 0x100e020)
        self.mu.mem_write(0x100e000, b'\xc3')
        self.mu.mem_write(0x100e020, b'\xc2\x0c\x00')
        self.mu.hook_add(UC_HOOK_CODE, self.record_waypoints, begin=0x100e020, end=0x100e020)
        self.mu.hook_add(UC_HOOK_CODE, self.has_waypoints, begin=0x100e000, end=0x100e000)

    def has_waypoints(self, mu, address, size, data):
        mu.reg_write(UC_X86_REG_EAX, int(bool(self.waypoints)))

    def record_waypoints(self, mu, address, size, data):
        pointer = self.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        for i, (x, z) in enumerate(self.waypoints):
            self.write(pointer + i * 12, x)
            self.write(pointer + i * 12 + 4, 0)
            self.write(pointer + i * 12 + 8, z)

    def steer(self, data):
        self.waypoints = data['waypoints']
        self.write(MOTION + 0x20, data['speed'])
        self.write(DEFINITION + 0x192, data['max_speed'])
        self.write(DEFINITION + 0x19a, data['brake'])
        self.write(DEFINITION + 0x19e, data['acceleration'])
        self.short(DEFINITION + 0x1ba, data['turn_rate'])
        self.write(DEFINITION + 0x241, data['unit_flags'])
        self.short(UNIT + 0x66, data['heading'])
        self.short(UNIT + 0x68, data['pitch'])
        self.write(UNIT + 0x6a, data['position'][0])
        self.write(UNIT + 0x6e, data['height_integer'] << 16)
        self.write(UNIT + 0x72, data['position'][1])
        self.write(UNIT + 0x110, 0)
        self.mu.mem_write(GAME + 0x1427f, bytes([data['sea_level']]))
        self.call(0x43cd20, [UNIT], this=MOTION, timeout=0)
        return dict(speed=signed(self.read(MOTION + 0x20)),
                    heading=self.read(UNIT + 0x66) & 65535,
                    turn_step=struct.unpack('<h', self.mu.mem_read(MOTION + 0x24, 2))[0],
                    velocity=[signed(self.read(MOTION + offset)) for offset in (8, 12, 16)])

    def short(self, address, value):
        self.mu.mem_write(address, struct.pack('<H', value & 65535))

    def record_callback(self, mu, address, size, data):
        pointer = self.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        self.callbacks.append(bytes(mu.mem_read(pointer, 32)).split(b'\0')[0].decode('ascii'))

    def speed(self, data):
        self.write(MOTION + 0x20, data['speed'])
        self.write(DEFINITION + 0x192, data['max_speed'])
        self.write(DEFINITION + 0x241, data['unit_flags'])
        self.short(UNIT + 0x66, data['heading'])
        self.short(UNIT + 0x68, data['pitch'])
        self.short(UNIT + 0x70, data['height_integer'])
        self.mu.mem_write(GAME + 0x1427f, bytes([data['sea_level']]))
        self.call(0x43cc20, [UNIT, data['acceleration']], this=MOTION, timeout=0)
        return dict(speed=signed(self.read(MOTION + 0x20)),
                    velocity=[signed(self.read(MOTION + offset)) for offset in (8, 12, 16)])

    def animation(self, data):
        self.write(MOTION + 0x20, data['speed'])
        self.short(MOTION + 0x24, data['turn_step'])
        self.mu.mem_write(MOTION + 0x2e, bytes([data['movement_flags']]))
        self.write(UNIT + 0x86, UNIT if data['attached'] else 0)
        self.write(UNIT + 0x110, data['unit_flags'])
        self.write(DEFINITION + 0x1ae, data['rate1'])
        self.write(DEFINITION + 0x1b2, data['rate2'])
        self.callbacks = []
        self.call(0x43da70, [UNIT], this=MOTION, timeout=0)
        return dict(unit_flags=self.read(UNIT + 0x110), callbacks=self.callbacks.copy())

    def parse_fixed(self, value):
        # A one-entry sorted TDF property collection; execute the original parser.
        self.write(0x1008019, 0x1009000)
        self.write(0x100801d, 0x1009008)
        self.write(0x1009000, 0x100a000)
        self.write(0x1009004, 0x100a100)
        self.mu.mem_write(0x100a000, b'value\0')
        self.mu.mem_write(0x100a100, value.encode('ascii') + b'\0')
        self.call(0x4c4800, [0x100b000, 0x100a000, 0], this=0x1008000, timeout=0)
        return signed(self.read(0x100b000))


def speed_cases():
    base = dict(speed=0, acceleration=9830, max_speed=78643, pitch=0,
                heading=0, height_integer=0, sea_level=0, unit_flags=0)
    # Reach/cruise/brake on land and underwater, carrying original output forward.
    yield 'stationary', dict(base, acceleration=0)
    for pitch, height, flags in itertools.product(
            [-32768, -10241, -10240, -2049, -2048, -1, 0, 2047, 2048, 10239, 10240, 32767],
            [-1, 0, 1], [0, 0x1000, 0x80000, 0x81000]):
        yield 'slope-water-cap', dict(base, speed=78643, pitch=pitch, height_integer=height, unit_flags=flags)
    # Exercise quantization boundaries on all 512 table steps, including wrap.
    for heading in range(0, 65536, 128):
        for offset in [-33, -32, -31, 0, 95, 96, 97]:
            yield 'heading-boundary', dict(base, speed=78643, heading=(heading + offset) & 65535)
    rng = random.Random(20260913)
    for _ in range(1000):
        yield 'mixed', dict(base, speed=rng.randrange(0, 5 * 65536),
                            acceleration=rng.randrange(-65536, 65536),
                            max_speed=rng.randrange(1, 8 * 65536),
                            heading=rng.randrange(65536), pitch=rng.randrange(-32768, 32768),
                            height_integer=rng.randrange(-100, 256), sea_level=rng.randrange(256),
                            unit_flags=rng.choice([0, 0x1000, 0x80000, 0x81000]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=Path('local/original/TotalA.exe'))
    parser.add_argument('--cob', type=Path, default=Path('local/viewer-assets/armcom.cob'))
    parser.add_argument('--output', type=Path, default=Path('local/movement/native-trace.json'))
    args = parser.parse_args()
    native = MovementReference(args.exe.read_bytes(), args.cob.read_bytes())
    fixed_values = {value: native.parse_fixed(value) for value in ['1.2', '0.3', '0.15', '1', '-0.15']}
    if fixed_values != {'1.2': 78643, '0.3': 19660, '0.15': 9830, '1': 65536, '-0.15': -9830}:
        raise AssertionError(f'Unexpected native fixed-point parsing: {fixed_values}')
    cases = []
    for label, data in speed_cases():
        cases.append(dict(kind='speed', label=label, input=data, expected=native.speed(data)))
    for underwater in [False, True]:
        speed = 0
        for tick in range(30):
            data = dict(speed=speed, acceleration=9830 if tick < 20 else -19660,
                        max_speed=78643, pitch=0, heading=20000,
                        height_integer=-1 if underwater else 0, sea_level=0, unit_flags=0)
            result = native.speed(data)
            cases.append(dict(kind='speed', label=f'continuous-{underwater}-{tick}', input=data, expected=result))
            speed = result['speed']
    for previous, speed, turn, blocked, attached in itertools.product(
            range(4), [-1, 0, 1, 100, 101, 200, 201], [0, 1, -1], [False, True], [False, True]):
        data = dict(unit_flags=0xabcdef03 | previous << 2, speed=speed, turn_step=turn,
                    movement_flags=4 if blocked else 0, attached=attached, rate1=100, rate2=200)
        cases.append(dict(kind='animation', label='state-transition', input=data, expected=native.animation(data)))
    rng = random.Random(430020)
    for index in range(1200):
        position = [200 * 65536, 300 * 65536]
        waypoints = [[position[0] + rng.randrange(-100, 100) * 65536, position[1] + rng.randrange(-100, 100) * 65536] for _ in range(3)]
        if index % 10 == 0:
            waypoints = []
        data = dict(position=position, waypoints=waypoints, speed=rng.randrange(78644),
                    max_speed=78643, acceleration=9830, brake=19660, turn_rate=1044,
                    heading=rng.randrange(65536), pitch=0, height_integer=0, sea_level=0, unit_flags=0)
        cases.append(dict(kind='steering', label=f'waypoint-{index}', input=data, expected=native.steer(data)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(exe_sha256=EXE_HASH, fixed_values=fixed_values,
                                         sine=list(native.sine), cases=cases)), encoding='utf-8')
    print(f'NATIVE_MOVEMENT_REFERENCE {len(cases)} cases; 512 regenerated sine entries match')


if __name__ == '__main__':
    main()
