"""Original weapon hit path 0x499cd0 -> 0x489bb0 -> 0x489ce0 with recorded COB script starts.

0x499cd0(projectile, unit, float scale) runs unmodified end to end: default damage lookup (null per-unit table),
float scale + ftol, attacker veterancy, game flags, hit angle (0x4b715a fpatan), 0x489bb0 ARMORED/damagemodifier
and target veterancy, the 9-byte damage packet, and 0x489ce0 health subtraction / dying flag / script starts.

Boundaries replaced (each with the original stdcall/thiscall return size):
  0x4b0a70 ScriptCall (thiscall, ret 0x20): recorder; the COB thread queue lives outside this oracle.
  0x406f80 damage statistics (ret 0xc): calls 0x4897b0, reads unit def +0x245 and player tables -> recorder.
  0x494ff0 local-player stat counter (ret 4): mutates a global .data counter array -> recorder.
  0x406f50 kill statistics (ret 0xc): not on this path; stubbed and asserted unreached.
  0x451df0 network send (ret 0xc): only for owner type 3; owners are type 1/2 so it is asserted unreached.
0x467950 (writes unit+0xfa = 0xf0), 0x4b7123/0x4b70ef (sine table), 0x4e43a0 (ftol) and 0x4e43d0 (s64 sar) run natively.
Paralyzer (type 2) cases set unit def +0x241 bit 0x4000000 so the paralyze order allocation at 0x489e49 is not reached.
"""
import json
import math
from pathlib import Path
import random
import struct

from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_ECX
from cob import signed

REGION = 0x2000000
UNITS = REGION                   # unit array, 0x118 per slot
DEFINITIONS = REGION + 0x10000   # unit definitions, 0x300 per slot
WEAPON = REGION + 0x20000
PROJECTILE = REGION + 0x21000
RECORDS = REGION + 0x22000       # player records, 0x14b each
SCRIPTS = REGION + 0x30000       # opaque script object pointers (never dereferenced: 0x4b0a70 is recorded)
SLOTS = 12
UNIT_SIZE = 0x118
DEF_SIZE = 0x300
REC_SIZE = 0x14b


def s16(value):
    value &= 0xffff
    return value - 0x10000 if value & 0x8000 else value


class HitNotify(MovementReference):
    def __init__(self, executable, cob):
        super().__init__(executable, cob)
        self.mu.mem_map(REGION, 0x40000)
        self.write(GAME + 0x14357, UNITS)
        self.scripts, self.packets, self.stats = [], [], []
        self.unreached = {0x406f50: 'kill statistics', 0x451df0: 'network send'}
        for address, size in [(0x4b0a70, 0x20), (0x406f80, 0xc), (0x494ff0, 4), (0x406f50, 0xc), (0x451df0, 0xc)]:
            self.mu.mem_write(address, b'\xc2' + struct.pack('<H', size))
        self.mu.hook_add(UC_HOOK_CODE, self.script_call, begin=0x4b0a70, end=0x4b0a70)
        self.mu.hook_add(UC_HOOK_CODE, self.packet, begin=0x489ce0, end=0x489ce0)
        self.mu.hook_add(UC_HOOK_CODE, self.stat(0x406f80, 3), begin=0x406f80, end=0x406f80)
        self.mu.hook_add(UC_HOOK_CODE, self.stat(0x494ff0, 1), begin=0x494ff0, end=0x494ff0)
        for address in self.unreached:
            self.mu.hook_add(UC_HOOK_CODE, self.forbidden, begin=address, end=address)

    def args(self, count):
        sp = self.mu.reg_read(UC_X86_REG_ESP)
        return [signed(self.read(sp + 4 + 4 * i)) for i in range(count)]

    def script_call(self, mu, address, size, data):
        args = self.args(8)
        name = bytes(mu.mem_read(args[0] & 0xffffffff, 32)).split(b'\0')[0].decode('ascii')
        self.scripts.append(dict(name=name, object=mu.reg_read(UC_X86_REG_ECX), args=args[1:]))

    def packet(self, mu, address, size, data):
        pointer = self.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        raw = bytes(mu.mem_read(pointer, 9))
        code, target, attacker, damage, angle, kind = struct.unpack('<BHHHBB', raw)
        self.packets.append(dict(code=code, target=target, attacker=attacker, damage=damage, angle=angle, type=kind))

    def stat(self, address, count):
        def hook(mu, _address, size, data):
            self.stats.append([address, *self.args(count)])
        return hook

    def forbidden(self, mu, address, size, data):
        raise RuntimeError(f'Unexpected call to {self.unreached[address]} {address:#x}')

    def unit(self, index):
        return UNITS + index * UNIT_SIZE

    def run(self, case):
        self.mu.mem_write(REGION, bytes(0x30000))
        self.mu.mem_write(GAME + 0x37f2f, struct.pack('<H', case['game_flags']))
        self.mu.mem_write(GAME + 0x2a42, bytes([case['local_player']]))
        for role in ('target', 'attacker'):
            data = case[role]
            if data is None:
                continue
            index = data['index']
            unit, definition, record = self.unit(index), DEFINITIONS + index * DEF_SIZE, RECORDS + index * REC_SIZE
            self.write(unit + 0x6a, data['position'][0])
            self.write(unit + 0x6e, data['position'][1])
            self.write(unit + 0x72, data['position'][2])
            self.mu.mem_write(unit + 0x66, struct.pack('<H', data['heading']))
            self.write(unit + 0x92, definition)
            self.write(unit + 0x96, record)
            self.write(unit + 0x9a, SCRIPTS + index)
            self.mu.mem_write(unit + 0xa8, struct.pack('<H', index))
            self.mu.mem_write(unit + 0xb8, struct.pack('<H', data['veterancy']))
            self.mu.mem_write(unit + 0xff, bytes([data['owner']]))
            self.mu.mem_write(unit + 0x108, struct.pack('<H', data['health'] & 0xffff))
            self.mu.mem_write(unit + 0x10e, bytes([2 if data['armored'] else 0]))
            self.write(unit + 0x110, data['flags'])
            self.write(definition + 0x1aa, data['modifier'])
            self.write(definition + 0x1fa, data['maxdamage'])
            self.write(definition + 0x241, data['def_flags'])
            self.write(record, 1 if data['record_active'] else 0)
            self.mu.mem_write(record + 0x73, bytes([data['record_type']]))
        self.write(WEAPON + 0x64, 0)
        self.mu.mem_write(WEAPON + 0xd4, struct.pack('<H', case['default_damage']))
        self.write(WEAPON + 0x111, case['weapon_flags'])
        self.write(PROJECTILE, WEAPON)
        for axis, value in enumerate(case['projectile']):
            self.write(PROJECTILE + 4 + 4 * axis, value)
        self.write(PROJECTILE + 0x52, self.unit(case['attacker']['index']) if case['attacker'] else 0)
        self.scripts, self.packets, self.stats = [], [], []
        scale_bits = struct.unpack('<I', struct.pack('<f', case['scale']))[0]
        returned = signed(self.call(0x499cd0, [PROJECTILE, self.unit(case['target']['index']), scale_bits], timeout=0))
        target = self.unit(case['target']['index'])
        flags = self.read(target + 0x110)
        if len(self.packets) != 1 or self.packets[0]['code'] != 0x0b:
            raise AssertionError(f'Expected one damage packet, got {self.packets}')
        return dict(returned=returned, packet=self.packets[0], health=s16(struct.unpack('<H', self.mu.mem_read(target + 0x108, 2))[0]),
                    dying=bool(flags & 0x4000), flags=flags, hit_flag=self.mu.mem_read(target + 0xfa, 1)[0],
                    type_byte=self.mu.mem_read(target + 0xf5, 1)[0], scripts=self.scripts, stats=self.stats)


def fixed(rng):
    return rng.randrange(-0x80000000, 0x80000000)


def predicted_damage(case):
    """Recovered default-table formula, used only to aim health at exact-zero / one-left results."""
    d = math.trunc(case['default_damage'] * case['scale'])
    target = case['target']
    if target['armored'] and d < 30000:
        d = (d * target['modifier']) >> 16
    return d


def float32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def build_cases():
    rng = random.Random(0x489ce0)
    cases = []

    def unit(index, kind):
        return dict(index=index, position=[0, 0, 0], heading=rng.randrange(65536), veterancy=0, owner=rng.randrange(4),
                    health=rng.randrange(1, 32768), armored=False, modifier=0x10000, maxdamage=rng.randrange(1, 70000),
                    flags=0x10000000 | (rng.randrange(0x10000) & ~0x4000), def_flags=0, record_active=True, record_type=kind)

    def direction(mode):
        if mode == 'axis':
            size = rng.choice([1, rng.randrange(1, 64) << 16, rng.randrange(1, 0x40000000)])
            return rng.choice([[size, 0], [-size, 0], [0, size], [0, -size], [0, 0]])
        if mode == 'diagonal':
            size = rng.choice([1, rng.randrange(1, 64) << 16, rng.randrange(1, 0x40000000)])
            return [rng.choice([size, -size]), rng.choice([size, -size])]
        if mode == 'large':
            return None
        if mode == 'fraction':
            return [rng.randrange(-0x10000, 0x10001), rng.randrange(-0x10000, 0x10001)]
        return [rng.randrange(-200 << 16, 200 << 16), rng.randrange(-200 << 16, 200 << 16)]

    def make(category, index):
        target_index, attacker_index = rng.sample(range(1, SLOTS), 2)
        target = unit(target_index, 1)
        attacker = unit(attacker_index, rng.choice([1, 2])) if rng.randrange(4) else None
        mode = rng.choice(['axis', 'diagonal', 'large', 'fraction', 'random', 'random'])
        delta = direction(mode)
        target['position'] = [fixed(rng), fixed(rng), fixed(rng)]
        if delta is None:
            projectile = [fixed(rng), fixed(rng), fixed(rng)]
        else:
            projectile = [signed((target['position'][0] + delta[0]) & 0xffffffff), fixed(rng),
                          signed((target['position'][2] + delta[1]) & 0xffffffff)]
        if attacker:
            attacker['position'] = [fixed(rng), fixed(rng), fixed(rng)]
        scale = 1.0 if index % 2 == 0 else float32(rng.choice([rng.uniform(0, 4), rng.uniform(0, 1), rng.randrange(1, 9) / 8]))
        case = dict(category=category, direction=mode, scale=scale, projectile=projectile, target=target, attacker=attacker,
                    default_damage=rng.choice([0, 1, rng.randrange(1, 200), rng.randrange(200, 5000), rng.randrange(29000, 31000), rng.randrange(65536)]),
                    weapon_flags=rng.randrange(0x10000) & ~0x80, game_flags=0, local_player=rng.randrange(6))
        armor = rng.randrange(4)
        if armor:
            target['armored'] = True
            target['modifier'] = [0x8000, 0x10000, rng.randrange(0, 0x20000)][armor - 1]
        elif rng.randrange(4) == 0:
            target['modifier'] = rng.randrange(0, 0x20000)  # ignored while not ARMORED
        health_mode = rng.choice(['random', 'random', 'lethal', 'zero', 'one-left', 'small'])
        damage = predicted_damage(case) & 0xffff
        if health_mode == 'lethal':
            target['health'] = rng.randrange(1, max(2, min(damage, 32768)))
        elif health_mode == 'zero' and 0 < damage < 32768:
            target['health'] = damage
        elif health_mode == 'one-left' and damage < 32767:
            target['health'] = damage + 1
        elif health_mode == 'small':
            target['health'] = rng.randrange(1, 200)
            target['maxdamage'] = rng.choice([1, target['health'], rng.randrange(1, 400)])
        case['health_mode'] = health_mode
        return case

    for index in range(2400):
        cases.append(make('core', index))
    for index in range(500):
        case = make('veterancy', index)
        case['target']['veterancy'] = rng.choice([0, rng.randrange(40), rng.randrange(65536)])
        if case['attacker']:
            case['attacker']['veterancy'] = rng.choice([0, rng.randrange(40), rng.randrange(65536)])
        case['game_flags'] = rng.choice([0x80, 0x100, 0x180, rng.randrange(0x10000)])
        cases.append(case)
    for index in range(150):
        case = make('paralyzer', index)
        case['weapon_flags'] |= 0x80
        case['target']['def_flags'] = 0x4000000 | rng.randrange(0x10000)
        cases.append(case)
    for index in range(150):
        case = make('inactive-owner', index)
        case['target']['record_active'] = False
        cases.append(case)
    # Audit additions (appended so the cases above keep their draws).
    for index in range(200):
        # 0x489d3f..0x489d53: dead (0x4000) or not-alive (no 0x10000000) targets return before health/scripts.
        case = make('gated', index)
        flags = case['target']['flags']
        case['target']['flags'] = rng.choice([flags & ~0x10000000, flags | 0x4000, (flags & ~0x10000000) | 0x4000])
        cases.append(case)
    for index in range(200):
        # Active owner record whose +0x73 is neither 1 nor 2 (and not 3, the network path): lethal hits clamp to 0.
        case = make('owner-type', index)
        case['target']['record_type'] = rng.choice([0, rng.randrange(4, 256)])
        if index % 3 == 0:
            case['weapon_flags'] |= 0x80
            case['target']['def_flags'] = 0x4000000
        cases.append(case)
    for index in range(120):
        # ARMORED 30000 boundary at scale 1.0 (0x489bd1 cmp edi, 0x7530; jge).
        case = make('armor-boundary', 0)
        case['default_damage'] = 29998 + index % 4
        case['target']['armored'] = True
        case['target']['modifier'] = rng.choice([0x8000, 0x10000, rng.randrange(0, 0x20000)])
        if index % 2:
            case['target']['health'] = rng.randrange(1, 32768)
        cases.append(case)
    # Owner record type 2 for the target on a separate stream (0x489ed8/0x489e2b), leaving geometry unchanged.
    types = random.Random(0x489e2b)
    for case in cases:
        if case['target']['record_type'] == 1 and types.randrange(2):
            case['target']['record_type'] = 2
    return cases


def main():
    native = HitNotify(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    cases = build_cases()
    for case in cases:
        case['expected'] = native.run(case)
    folder = Path('local/combat')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native-hit-notify.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, sine=list(native.sine), cases=cases)), encoding='utf-8')
    counts = {}
    for case in cases:
        counts[case['category']] = counts.get(case['category'], 0) + 1
    lethal = sum(1 for case in cases if case['expected']['dying'])
    zero = sum(1 for case in cases if case['category'] == 'core' and case['expected']['health'] == 0)
    scripted = sum(1 for case in cases if case['expected']['scripts'])
    print(f'NATIVE_HIT_NOTIFY {len(cases)} cases {counts}; {lethal} dying, {zero} core exact-zero, {scripted} with script calls, '
          f'{sum(len(case["expected"]["stats"]) for case in cases)} stat stubs hit')


if __name__ == '__main__':
    main()
