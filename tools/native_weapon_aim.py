"""Original weapon Aim request state machine: 0x49e1a0 with fire callbacks 0x49d580/0x49db70 over many ticks.

Runs, unmodified: the per-slot weapon update 0x49e1a0, target resolver 0x48a1e0 (with terrain sampler 0x485070 and
the dead-target TargetCleared start), range gate 0x49aa80, ballistic solver 0x49a890, integer atan 0x4b715a, the
line-of-sight angle solver 0x49d910, turret fire callback 0x49d580 with tolerance 0x49d880 and spread RNG 0x4b6c30,
vlaunch fire callback 0x49db70, callback installer 0x49e010, the script start helpers 0x4b0a70 -> 0x4b0b00 ->
allocator 0x4b08c0 (against a fake eight-slot script context) and the completion callback reached through the
completion object's vtable 0x4fd6f0 (0x481490).

Replaced (each a documented stub that records its arguments):
- 0x43e2e0 AimFrom world point, 0x43e240 muzzle world point, 0x43e3c0 target SweetSpot point: synchronous COB piece
  queries; they write the scenario's per-tick points (the fake COB layer owns scripts).
- 0x49cde0 / 0x49c9c0 / 0x49cc20 projectile launchers: record the entry's stored heading/pitch and return the
  scenario's launch result (the real launchers also start Fire* with run-now 0; that start is not modelled).
- 0x4012a0 per-shot resource payment (thiscall, ret 8): recorder.
- 0x456200 network Aim echo (ret 0x1c): recorder. Game+0x2a44 = 0 so 0x451df0 packets are skipped by the code itself.
- The COB scheduler pass 0x4b0d60 (called at 0x48adeb right after 0x49e1a0 in the unit update) is replaced by the
  fake COB layer: every thread started by 0x4b0b00 is taken over after the call and, per scripted response, returns
  a value after N passes (invoking the completion object's vtable[0] natively), is killed after N passes without a
  callback (SIGNAL), or never finishes (its slot stays busy). A 'drop' response fills every free slot so the
  original allocator fails and 0x4b0b00 calls the completion with 0 itself.

Writes local/weapon-aim/native-weapon-aim.json (ignored) and prints a summary.
"""
import hashlib
import json
import random
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'local/python-deps'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_ECX, UC_X86_REG_EIP, UC_X86_REG_ESP,
                               UC_X86_REG_FPCW, UC_X86_REG_FPSW, UC_X86_REG_FPTAG)
from inspect_install import inspect_pe

EXE_HASH = '3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e'
CTX = 0x1000000
SCRIPT = 0x1001000
NAMES = 0x1001100
STRINGS = 0x1001200
CODE = 0x1001800
UNIT = 0x1010000
UNIT_DEF = 0x1011000
WEAPON = 0x1012000
TARGETS = 0x1020000
RESOURCES = 0x1030000
GRID = 0x1040000
PAYMENT = 0x1050000
GAME = 0x1400000
STOP = 0x1e00000
STACK_TOP = 0x1eff000
RNG_SEED = 0x51fc88
COMPLETION_VTABLE = 0x4fd6f0
UNIT_STRIDE = 0x118
SLOT_NAMES = ['Primary', 'Secondary', 'Tertiary']
MAP_CELLS = 64
TURRET, BALLISTIC, LINE, VLAUNCH = 0x80000, 0x2, 0x1, 0x10


def signed16(value):
    value &= 0xffff
    return value - 0x10000 if value & 0x8000 else value


def signed32(value):
    value &= 0xffffffff
    return value - 0x100000000 if value & 0x80000000 else value


class WeaponAim:
    def __init__(self, executable):
        if hashlib.sha256(executable).hexdigest() != EXE_HASH:
            raise ValueError('This oracle only supports the recorded executable SHA-256')
        mu = self.mu = Uc(UC_ARCH_X86, UC_MODE_32)
        mu.mem_map(0x400000, 0x200000)
        mu.mem_write(0x400000, executable[:1024])
        for section in inspect_pe(executable)['sections']:
            mu.mem_write(0x400000 + section['rva'], executable[section['raw_offset']:section['raw_offset'] + section['raw_size']])
        mu.mem_map(CTX, 0x100000)
        mu.mem_map(GAME, 0x40000)
        mu.mem_map(STOP, 0x200000)
        mu.mem_write(STOP, b'\xc3')
        self.write(0x511de8, GAME)
        for address, name, ret in [(0x43e2e0, 'aimfrom', 0xc), (0x43e240, 'muzzle', 0x10), (0x43e3c0, 'sweetspot', 8),
                                   (0x49cde0, 'launch', 0x14), (0x49c9c0, 'launch', 0x14), (0x49cc20, 'launch', 0x18),
                                   (0x4012a0, 'payment', 8), (0x456200, 'net', 0x1c)]:
            mu.mem_write(address, b'\xc2' + struct.pack('<H', ret))
            mu.hook_add(UC_HOOK_CODE, self.stub, begin=address, end=address, user_data=name)
        for address, name in [(0x4b0a70, 'start'), (0x4b0b25, 'allocated'), (0x4b0b1f, 'refused'), (0x49d580, 'attempt'),
                              (0x49db70, 'attempt'), (0x49e43f, 'fired'), (0x49e3cd, 'range')]:
            mu.hook_add(UC_HOOK_CODE, self.probe, begin=address, end=address, user_data=name)
        assert self.read(COMPLETION_VTABLE) == 0x481490

    def read(self, address):
        return struct.unpack('<I', self.mu.mem_read(address, 4))[0]

    def write(self, address, value):
        self.mu.mem_write(address, struct.pack('<I', value & 0xffffffff))

    def word(self, address):
        return struct.unpack('<H', self.mu.mem_read(address, 2))[0]

    def put_word(self, address, value):
        self.mu.mem_write(address, struct.pack('<H', value & 0xffff))

    def cstring(self, address):
        data = bytes(self.mu.mem_read(address, 32))
        return data[:data.index(b'\0')].decode('ascii')

    def call(self, address, args, this=0):
        sp = STACK_TOP - (len(args) + 1) * 4
        self.write(sp, STOP)
        for i, value in enumerate(args):
            self.write(sp + 4 + i * 4, value)
        mu = self.mu
        mu.reg_write(UC_X86_REG_ESP, sp)
        mu.reg_write(UC_X86_REG_ECX, this)
        mu.reg_write(UC_X86_REG_FPCW, 0x37f)
        mu.reg_write(UC_X86_REG_FPSW, 0)
        mu.reg_write(UC_X86_REG_FPTAG, 0xffff)
        mu.emu_start(address, STOP, count=5000000)
        if mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError(f'{address:#x} did not return')
        return mu.reg_read(UC_X86_REG_EAX)

    def arg(self, index):
        return self.read(self.mu.reg_read(UC_X86_REG_ESP) + 4 + index * 4)

    def point(self, out, value):
        for axis in range(3):
            self.write(out + axis * 4, value[axis])

    def stub(self, mu, address, size, name):
        inputs = self.inputs
        if name == 'aimfrom':
            self.point(self.arg(1), inputs['aim'])
        elif name == 'muzzle':
            self.point(self.arg(1), inputs['muzzle'])
        elif name == 'sweetspot':
            self.point(self.arg(1), inputs['target_point'])
        elif name == 'launch':
            entry = self.entry
            self.record['launches'].append(dict(heading=self.word(entry + 0x16), pitch=self.word(entry + 0x18),
                                                unit_heading=self.word(UNIT + 0x66), ok=int(inputs['launch'])))
            mu.reg_write(UC_X86_REG_EAX, int(inputs['launch']))
        elif name == 'payment':
            self.record['payments'] += 1
        elif name == 'net':
            self.record['net'].append([signed32(self.arg(i)) for i in (2, 3, 4)])

    def probe(self, mu, address, size, name):
        record = self.record
        if name == 'start':
            start = dict(name=self.cstring(self.arg(0)), completion=int(self.arg(1) != 0), run_now=self.arg(2),
                         argc=self.arg(3), args=[signed32(self.arg(4 + i)) for i in range(4)], started=False)
            record['starts'].append(start)
        elif name == 'allocated':
            record['starts'][-1]['started'] = True
            record['starts'][-1]['slot'] = mu.reg_read(UC_X86_REG_EAX)
        elif name == 'refused':
            record['starts'][-1]['started'] = False
        elif name == 'attempt':
            record['attempts'].append(None)
        elif name == 'fired':
            record['attempts'][-1] = mu.reg_read(UC_X86_REG_EAX) & 0xff
        elif name == 'range':
            record['range_ok'] = int(mu.reg_read(UC_X86_REG_EAX) != 0)

    def setup(self, case):
        mu = self.mu
        mu.mem_write(CTX, bytes(0x100000))
        mu.mem_write(GAME, bytes(0x40000))
        self.write(0x511de8, GAME)
        functions = case['functions']
        self.write(CTX + 8, SCRIPT)
        self.write(SCRIPT + 4, len(functions))
        self.write(SCRIPT + 0x1c, NAMES)
        self.write(SCRIPT + 0x18, CODE)
        offset = STRINGS
        for index, name in enumerate(functions):
            mu.mem_write(offset, name.encode() + b'\0')
            self.write(NAMES + index * 4, offset)
            self.write(CODE + index * 4, 0x100 * (index + 1))
            offset += len(name) + 1
        self.write(GAME + 0x14233, MAP_CELLS)
        self.write(GAME + 0x14237, MAP_CELLS)
        self.write(GAME + 0x14287, GRID)
        grid = bytearray(MAP_CELLS * MAP_CELLS * 13)
        for index, height in enumerate(case['heights']):
            grid[index * 13 + 4] = height
        mu.mem_write(GRID, bytes(grid))
        mu.mem_write(GAME + 0x1427f, bytes([case['sea_level']]))
        self.write(GAME + 0x14263, case['gravity'])
        self.write(GAME + 0x14357, TARGETS)
        self.write(RNG_SEED, case['seed'])
        weapon = case['weapon']
        self.write(WEAPON + 0x68, weapon['speed'])
        mu.mem_write(WEAPON + 0xc0, struct.pack('<ff', weapon['energy'], weapon['metal']))
        mu.mem_write(WEAPON + 0xc8, struct.pack('<f', weapon['minimum_angle']))
        self.write(WEAPON + 0xdc, weapon['range'])
        self.put_word(WEAPON + 0xe4, weapon['reload'])
        self.put_word(WEAPON + 0x104, weapon['accuracy'])
        self.put_word(WEAPON + 0x106, weapon['tolerance'])
        self.put_word(WEAPON + 0x108, weapon['pitch_tolerance'])
        self.write(WEAPON + 0x111, weapon['flags'])
        self.call(0x49e010, [WEAPON])
        self.callback = self.read(WEAPON + 0x60)
        self.write(UNIT + 0x92, UNIT_DEF)
        self.write(UNIT + 0x9a, CTX)
        self.write(UNIT + 0xec, RESOURCES)
        self.write(UNIT_DEF + 0x1fa, case['maxdamage'])
        self.put_word(UNIT + 0x108, case['health'])
        self.put_word(UNIT + 0xb8, case['experience'])
        slot = case['slot']
        self.entry = UNIT + 4 + slot * 0x1c
        self.write(self.entry + 4, COMPLETION_VTABLE)
        self.write(self.entry + 0xc, WEAPON)
        mu.mem_write(self.entry + 0x1b, bytes([2 | slot << 2]))
        self.threads = []
        self.responses = list(case['responses'])

    def slot_busy(self, index):
        return self.read(CTX + 0x1c + index * 0xa4) != 0

    def tick(self, case, tick, inputs):
        self.inputs = inputs
        mu = self.mu
        entry = self.entry
        self.put_word(UNIT + 0x66, inputs['unit_heading'])
        self.point(UNIT + 0x6a, inputs['unit_position'])
        self.write(UNIT + 0x110, inputs['unit_flags'])
        mu.mem_write(RESOURCES + 0x8c, struct.pack('<f', inputs['energy']))
        mu.mem_write(RESOURCES + 0x98, struct.pack('<f', inputs['metal']))
        mu.mem_write(UNIT + 0xba, bytes(2))
        for index, alive in inputs['alive'].items():
            self.put_word(TARGETS + int(index) * UNIT_STRIDE + 0xa6, alive)
        if 'set_target' in inputs:
            self.put_word(entry, inputs['set_target'][0])
            self.put_word(entry + 2, inputs['set_target'][1])
        filled = []
        if self.responses and self.responses[0][0] == 'drop':
            for index in range(8):
                if not self.slot_busy(index):
                    self.write(CTX + 0x1c + index * 0xa4, 0xdead)
                    filled.append(index)
        self.record = record = dict(tick=tick, starts=[], attempts=[], launches=[], payments=0, net=[], callbacks=[])
        self.call(0x49e1a0, [UNIT])
        for index in filled:
            self.write(CTX + 0x1c + index * 0xa4, 0)
        for start in record['starts']:
            aim = start['name'].startswith('Aim')
            response = ('never',)
            if aim and start['name'] in case['functions']:
                response = tuple(self.responses.pop(0)) if self.responses else ('never',)
            elif not aim:
                response = ('kill', 1)
            if start['started']:
                slot = start['slot']
                record_base = CTX + slot * 0xa4
                thread = dict(slot=slot, completion=self.read(record_base + 0x3c), response=response, passes=0,
                              stack=[signed32(self.read(record_base + 0x40 + i * 4)) for i in range(4)],
                              sp=signed32(self.read(record_base + 0x24)))
                start['stack'] = thread['stack']
                start['sp'] = thread['sp']
                start['response'] = list(response)
                self.threads.append(thread)
            elif aim and response[0] != 'drop' and start['name'] in case['functions']:
                start['response'] = list(response)
        # State as left by 0x49e1a0, before this tick's script pass delivers completions.
        record.update(flags=mu.mem_read(entry + 0x1b, 1)[0], result=self.read(entry + 8), heading=self.word(entry + 0x16),
                      pitch=self.word(entry + 0x18), reload=self.word(entry + 0x14), range_flag=int(mu.mem_read(UNIT + 0xbb, 1)[0] & 0x10 != 0),
                      shot_flags=self.word(UNIT + 0xba), target=[self.word(entry), self.word(entry + 2)], seed=self.read(RNG_SEED),
                      busy=sum(1 for index in range(8) if self.slot_busy(index)))
        # Fake COB scheduler pass (native 0x4b0d60 at 0x48adeb runs right after 0x49e1a0 in the same unit update).
        survivors = []
        for thread in self.threads:
            thread['passes'] += 1
            kind = thread['response'][0]
            if kind in ('complete', 'kill') and thread['passes'] >= thread['response'][-1]:
                if kind == 'complete' and thread['completion']:
                    before = self.read(entry + 8)
                    self.call(self.read(self.read(thread['completion'])), [thread['response'][1]], this=thread['completion'])
                    record['callbacks'].append(dict(value=thread['response'][1], before=before, after=self.read(entry + 8)))
                self.write(CTX + 0x1c + thread['slot'] * 0xa4, 0)
                self.write(CTX + 0x53c, max(0, signed32(self.read(CTX + 0x53c)) - 1))
                continue
            survivors.append(thread)
        self.threads = survivors
        return record


def make_case(rng, index):
    kind = ['ballistic', 'line', 'line', 'ballistic', 'vlaunch', 'ballistic', 'line', 'vlaunch', 'line', 'unsolvable'][index % 10]
    flags = {'ballistic': TURRET | BALLISTIC, 'line': TURRET | LINE, 'vlaunch': VLAUNCH | LINE, 'unsolvable': TURRET}[kind]
    if kind == 'line' and rng.random() < 0.3:
        flags |= 0x100000  # selfprop: direct launcher 0x49c9c0 path in the turret callback
    tolerance = rng.choice([0, 0, 0, 1, 100, 150, 2000, 6000, 40000])
    pitch_tolerance = rng.choice([0, 0, 50, 3000]) if tolerance else rng.choice([0, 0, 700])
    weapon = dict(flags=flags, speed=rng.choice([371370, 655359, 655359, 200000 if rng.random() < 0.1 else 655359]), minimum_angle=struct.unpack('<f', struct.pack('<f', -0.19634954631328583))[0],
                  range=rng.choice([180, 300, 600]), reload=rng.choice([0, 1, 2, 5, 12, 30]), accuracy=rng.choice([0, 0, 300, 1200]),
                  tolerance=tolerance, pitch_tolerance=pitch_tolerance, energy=rng.choice([0.0, 0.0, 50.0]), metal=rng.choice([0.0, 0.0, 2.0]))
    functions = ['Create', 'TargetCleared']
    slot = rng.choice([0, 0, 0, 2])
    if rng.random() > 0.08:
        functions.append('Aim' + SLOT_NAMES[slot])
    functions += ['Query' + SLOT_NAMES[slot], 'Fire' + SLOT_NAMES[slot]]
    responses = []
    for _ in range(40):
        roll = rng.random()
        if roll < 0.6:
            responses.append(['complete', rng.choice([1, 1, 1, 2, 0]), rng.choice([1, 1, 2, 3, 6])])
        elif roll < 0.8:
            responses.append(['complete', rng.choice([1, 2]), rng.randrange(8, 25)])
        elif roll < 0.88:
            responses.append(['drop'])
        elif roll < 0.96:
            responses.append(['kill', rng.randrange(1, 10)])
        else:
            responses.append(['never'])
    heights = [rng.randrange(25, 70) for _ in range(MAP_CELLS * MAP_CELLS)]
    ticks = 150
    base = [rng.randrange(20, 40) * 16 * 65536, 40 * 65536, rng.randrange(20, 40) * 16 * 65536]
    moving_unit = rng.random() < 0.3
    turning = rng.random() < 0.3
    heading0 = rng.randrange(65536)
    targets = {3: dict(position=[base[0] + rng.randrange(-200, 200) * 65536, 45 * 65536, base[2] + rng.randrange(-200, 200) * 65536],
                       velocity=[rng.choice([0, 0, 20000, -40000]), 0, rng.choice([0, 0, 30000, -15000])], death=rng.choice([None, None, rng.randrange(30, 110)])),
               5: dict(position=[base[0] + rng.randrange(-150, 150) * 65536, 50 * 65536, base[2] + rng.randrange(-150, 150) * 65536],
                       velocity=[0, 0, 0], death=None)}
    ground = [signed16((base[0] >> 16) + rng.randrange(-120, 120)), signed16((base[2] >> 16) + rng.randrange(-120, 120))]
    plan = {0: [3, 0x8000]}
    choice = rng.random()
    if choice < 0.25:
        plan = {0: [ground[0] & 0xffff, ground[1] & 0xffff]}
    elif choice < 0.4:
        plan = {0: [3, 0x8000], rng.randrange(20, 80): [5, 0x8000]}
    elif choice < 0.5:
        plan = {0: [0, 0x8000], 10: [5, 0x8000], rng.randrange(40, 90): [0, 0x8000]}
    elif choice < 0.6:
        plan = {0: [5, 0x8000], rng.randrange(20, 60): [ground[0] & 0xffff, ground[1] & 0xffff]}
    aim_offset = [rng.randrange(-4, 5) * 65536, rng.randrange(8, 20) * 65536, rng.randrange(-4, 5) * 65536]
    muzzle_offset = [rng.randrange(-6, 7) * 65536, rng.randrange(6, 22) * 65536, rng.randrange(-6, 7) * 65536]
    stock_gap = rng.randrange(0, 120) if rng.random() < 0.3 else -1
    inputs = []
    current = None
    for tick in range(ticks):
        position = [base[0] + (tick * 30000 if moving_unit else 0), base[1], base[2] - (tick * 20000 if moving_unit else 0)]
        heading = (heading0 + (tick * rng.choice([0, 91, 400]) if turning else 0)) & 0xffff
        if tick in plan:
            current = plan[tick]
        alive = {}
        for key, target in targets.items():
            alive[str(key)] = 0 if target['death'] is not None and tick >= target['death'] else 1
        if current[1] == 0x8000 and current[0] in targets:
            target = targets[current[0]]
            target_point = [target['position'][axis] + target['velocity'][axis] * tick for axis in range(3)]
            target_point[1] += 12 * 65536
        else:
            target_point = [0, 0, 0]
        item = dict(unit_heading=heading, unit_position=position, unit_flags=rng.choice([0, 0, 0, 4, 8, 0xc, 1]) if tick == 0 else inputs[-1]['unit_flags'],
                    aim=[position[axis] + aim_offset[axis] for axis in range(3)], muzzle=[position[axis] + muzzle_offset[axis] for axis in range(3)],
                    target_point=target_point, alive=alive, launch=0 if rng.random() < 0.08 else 1,
                    energy=0.0 if 0 <= stock_gap <= tick < stock_gap + 20 else 1000.0, metal=1000.0)
        if tick in plan:
            item['set_target'] = plan[tick]
        inputs.append(item)
    return dict(index=index, kind=kind, weapon=weapon, functions=functions, slot=slot, responses=responses, heights=heights,
                sea_level=rng.choice([0, 0, 0, 30, 30, 30, 30, 30, 45]), gravity=rng.choice([4369, 4369, 8155]), seed=rng.randrange(1, 0x7fffffff),
                health=rng.choice([1000, 600, 90]), maxdamage=1000, experience=rng.choice([0, 0, 13, 40]), inputs=inputs)


def fixed_cases():
    """Hand-built stall/tolerance/re-aim cases on a flat map with a stationary ground target."""
    cases = []
    for name, responses, tolerance, flags110, turn in [
            ('drop-stall', [['drop'], ['complete', 1, 1]], 0, 0, 0),
            ('zero-return-stall', [['complete', 0, 1], ['complete', 1, 1]], 0, 0, 0),
            ('kill-stall', [['kill', 2], ['complete', 1, 1]], 0, 0, 0),
            ('return-2-aims', [['complete', 2, 3]] * 12, 0, 0, 0),
            ('tolerance-150-turning', [['complete', 1, 1]] * 60, 0, 0, 120),
            ('tolerance-2000-flags', [['complete', 1, 1]] * 60, 0, 4, 120),
            ('tolerance-explicit', [['complete', 1, 1]] * 60, 700, 0, 120),
            ('slow-aim-reaim-after-shot', [['complete', 1, 5]] * 30, 0, 0, 0)]:
        inputs = []
        for tick in range(90):
            position = [512 * 65536, 40 * 65536, 512 * 65536]
            inputs.append(dict(unit_heading=(32768 + tick * turn) & 0xffff, unit_position=position, unit_flags=flags110,
                               aim=[position[0], position[1] + 12 * 65536, position[2]], muzzle=[position[0], position[1] + 14 * 65536, position[2] + 3 * 65536],
                               target_point=[0, 0, 0], alive={'3': 1, '5': 1}, launch=1, energy=1000.0, metal=1000.0))
        inputs[0]['set_target'] = [(512 + 150) & 0xffff, 512]
        heights = [40] * (MAP_CELLS * MAP_CELLS)
        weapon = dict(flags=TURRET | BALLISTIC, speed=371370, minimum_angle=struct.unpack('<f', struct.pack('<f', -0.19634954631328583))[0],
                      range=300, reload=8, accuracy=0, tolerance=tolerance, pitch_tolerance=0, energy=0.0, metal=0.0)
        cases.append(dict(index=len(cases), name=name, kind='ballistic', weapon=weapon,
                          functions=['Create', 'TargetCleared', 'AimPrimary', 'QueryPrimary', 'FirePrimary'], slot=0,
                          responses=responses, heights=heights, sea_level=0, gravity=4369, seed=12345, health=1000, maxdamage=1000,
                          experience=0, inputs=inputs))
    return cases


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 360
    native = WeaponAim(Path('local/original/TotalA.exe').read_bytes())
    rng = random.Random(0x49e1a0)
    cases = fixed_cases()
    cases += [make_case(rng, index) for index in range(count)]
    totals = dict(ticks=0, aim_starts=0, dropped=0, callbacks=0, attempts=0, launches=0, target_cleared=0, range_flags=0, tolerance_clears=0)
    for position, case in enumerate(cases):
        case['index'] = position
        native.setup(case)
        records = []
        previous_flags = None
        for tick, inputs in enumerate(case['inputs']):
            record = native.tick(case, tick, inputs)
            records.append(record)
            totals['ticks'] += 1
            for start in record['starts']:
                if start['name'].startswith('Aim'):
                    totals['aim_starts'] += 1
                    totals['dropped'] += int(not start['started'])
                elif start['name'] == 'TargetCleared':
                    totals['target_cleared'] += 1
            totals['callbacks'] += len(record['callbacks'])
            totals['attempts'] += len(record['attempts'])
            totals['launches'] += sum(item['ok'] for item in record['launches'])
            totals['range_flags'] += record['range_flag']
            if record['attempts'] and not record['launches'] and previous_flags is not None and previous_flags & 1 and not record['flags'] & 1:
                totals['tolerance_clears'] += 1
            previous_flags = record['flags']
        case['records'] = records
    folder = Path('local/weapon-aim')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native-weapon-aim.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_WEAPON_AIM {len(cases)} cases; ' + ', '.join(f'{key}={value}' for key, value in totals.items()))


if __name__ == '__main__':
    main()
