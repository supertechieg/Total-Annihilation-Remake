"""End-to-end original cannon shot composition on real ballistic unit geometry.

Runs weapon initialization 0x49e070 (launch offset) at creation pose, the ballistic
aim path used by 0x49e1a0 (AimFrom, integer heading, 0x49a890), turret fire callback
0x49d580 (tolerance, muzzle query, accuracy, launcher 0x49cde0) and the original
projectile update 0x49b720 with collision stubbed. Script starts, RockUnit/SetMaxReloadTime
calls and launch sound are stubbed; pieces and statics come from recorded native firing poses.
"""
import json
import struct
import sys
from pathlib import Path
from native_movement_reference import MovementReference, UNIT, DEFINITION, GAME
from native_factory_reference import FactoryReference
from native_cob_reference import EXE_HASH, CONTEXT, STATICS, SCRIPT
from cob import signed

BASE = 0x1500000
MODEL, GEOMETRY, WEAPON, POOL, AIM, TARGET = BASE, BASE + 0x4000, BASE + 0x10000, BASE + 0x20000, BASE + 0x30000, BASE + 0x30100
GRAVITY = 4369


class CannonReference(MovementReference, FactoryReference):
    def __init__(self, executable, unit):
        root = Path('local/unit-assets') / unit
        super().__init__(executable, (root / 'script.cob').read_bytes())
        self.read_values[17] = 0
        self.mu.mem_map(BASE, 0x40000)
        self.program_json = json.loads((root / 'script.json').read_text())
        self.model = json.loads((root / 'unit.json').read_text())['model']
        for offset, count in [(0x1c, len(self.program_json['functions'])), (0x20, len(self.program_json['pieces']))]:
            table = self.read(SCRIPT + offset)
            for index in range(count):
                self.write(table + index * 4, SCRIPT + self.read(table + index * 4))
        self.write(CONTEXT + 0x540, MODEL)
        self.write(UNIT + 0x9e, MODEL)
        self.write(UNIT + 0x9a, CONTEXT)
        by_name = {piece['name'].lower(): piece for piece in self.model['pieces']}
        names = [name.lower() for name in self.program_json['pieces']]
        names += [name for name in by_name if name not in names]
        self.write(MODEL, len(names))
        for index, name in enumerate(names):
            piece = by_name[name]
            record, geometry = MODEL + 0x22 + index * 0x36, GEOMETRY + index * 0x40
            self.write(record, geometry)
            parent = piece['parent']
            self.write(record + 0x32, 0 if parent < 0 else MODEL + 0x22 + names.index(self.model['pieces'][parent]['name'].lower()) * 0x36)
            for axis in range(3):
                self.write(geometry + 0x10 + axis * 4, piece['offset'][axis])
            self.call(0x4cb590, [geometry])
        # Stubs outside shot composition: script-call-with-args, launch sound.
        self.mu.mem_write(0x4b0a70, b'\xc2\x20\x00')
        self.mu.mem_write(0x47f300, b'\xc2\x0c\x00')
        self.mu.mem_write(0x49b090, b'\xc2\x08\x00')
        self.mu.mem_write(0x49ae20, b'\xc3')
        # Three weapon slots share the primary definition.
        self.write(DEFINITION + 0x1ee, WEAPON)
        self.write(DEFINITION + 0x1f2, WEAPON)
        self.write(DEFINITION + 0x1f6, WEAPON)
        self.write(DEFINITION + 0x1fa, 1000)
        self.write(GAME + 0x14263, GRAVITY)
        self.write(GAME + 0x141f7, POOL)
        self.write(GAME + 0x2a44, 0)
        self.write(GAME + 0x142f3, 0)

    def pose(self, state):
        for index, value in enumerate(state['statics']):
            self.write(STATICS + index * 4, value)
        # Setters 0x480c50/0x480ce0 store position directly and rotation low 16 bits; write the records
        # directly as native_tank_targets.py does, avoiding one emulator entry per axis.
        for index, piece in enumerate(state['pieces']):
            record = MODEL + 0x22 + index * 0x36
            self.mu.mem_write(record + 4, struct.pack('<3i', *[signed(value & 0xffffffff) for value in piece['position']]))
            self.mu.mem_write(record + 0x10, struct.pack('<3H', *[value & 0xffff for value in piece['rotation']]))

    def weapon(self, definition, runtime):
        self.mu.mem_write(WEAPON, bytes(0x115))
        self.write(WEAPON + 0x68, runtime['velocity_raw_per_tick'])
        self.mu.mem_write(WEAPON + 0xc8, struct.pack('<f', runtime['minimum_barrel_angle']))
        self.mu.mem_write(WEAPON + 0xe4, struct.pack('<H', runtime['reload_ticks']))
        flags = 2 | (0x80000 if int(definition.get('turret', '0')) & 1 else 0)
        self.write(WEAPON + 0x111, flags)
        self.mu.mem_write(WEAPON + 0xe6, struct.pack('<H', int(float(definition.get('weapontimer', '0')) * 30) & 0xffff))
        self.mu.mem_write(WEAPON + 0xdc, struct.pack('<I', int(definition.get('range', '0'))))

    def engagement(self, unit_raw, unit_heading, target_raw, tick, ticks=90):
        """Create, capture the launch offset, aim with the original script until settled, then fire."""
        for axis in range(3):
            self.write(UNIT + 0x6a + axis * 4, unit_raw[axis])
        self.invoke('Create', [])
        create_state = self.snapshot()
        requests = []
        requested = None
        for step in range(ticks):
            self.short(UNIT + 0x66, unit_heading)
            self.pose(self.snapshot())
            self.call(0x43e2e0, [UNIT, AIM, 0])
            aim = [signed(self.read(AIM + axis * 4)) for axis in range(3)]
            delta = [(aim[axis] - target_raw[axis]) & 0xffffffff for axis in range(3)]
            heading = (self.call(0x4b715a, [delta[0], delta[2]]) - unit_heading) & 0xffff
            pitch = self.call(0x49a890, [delta[0], delta[1], delta[2], self.read(WEAPON + 0x68), self.read(WEAPON + 0xc8)]) & 0xffff
            if pitch != 0x8000 and (heading, pitch) != requested:
                self.invoke('AimPrimary', [heading, pitch])
                requested = (heading, pitch)
                requests.append(dict(step=step, heading=heading, pitch=pitch))
            self.step()
        fire_state = self.snapshot()
        return create_state, fire_state, requests

    def shot(self, create_state, fire_state, unit_raw, unit_heading, target_raw, tick):
        for axis in range(3):
            self.write(UNIT + 0x6a + axis * 4, unit_raw[axis])
        self.short(UNIT + 0x64, 0)
        self.short(UNIT + 0x68, 0)
        # Creation pose and default creation heading 32768 for the launch offset.
        self.short(UNIT + 0x66, 32768)
        self.mu.mem_write(UNIT + 4, bytes(0x60))
        self.pose(create_state)
        self.call(0x49e070, [UNIT])
        offset = signed(self.read(UNIT + 0x14))
        self.short(UNIT + 0x66, unit_heading)
        self.pose(fire_state)
        self.call(0x43e2e0, [UNIT, AIM, 0])
        aim = [signed(self.read(AIM + axis * 4)) for axis in range(3)]
        delta = [(aim[axis] - target_raw[axis]) & 0xffffffff for axis in range(3)]
        heading = (self.call(0x4b715a, [delta[0], delta[2]]) - unit_heading) & 0xffff
        pitch = self.call(0x49a890, [delta[0], delta[1], delta[2], self.read(WEAPON + 0x68), self.read(WEAPON + 0xc8)]) & 0xffff
        for axis in range(3):
            self.write(TARGET + axis * 4, target_raw[axis])
        controller = UNIT + 4
        self.write(controller + 8, 1)
        self.short(controller + 0x16, heading)
        self.short(controller + 0x18, pitch)
        self.mu.mem_write(controller + 0x1b, bytes([1]))
        self.short(UNIT + 0x108, 1000)
        self.short(UNIT + 0xb8, 0)
        self.write(UNIT + 0x110, 0)
        self.mu.mem_write(UNIT + 0xff, bytes([0]))
        self.write(GAME + 0x141f3, 0)
        self.write(GAME + 0x38a47, tick)
        self.mu.mem_write(POOL, bytes(0x6b))
        fired = self.call(0x49d580, [UNIT, controller, 0, TARGET])
        result = dict(offset=offset, aim=aim, heading=heading, pitch=pitch, fired=fired & 0xff,
                      launch_heading=self.read(controller + 0x16) & 0xffff)
        if result['fired'] and pitch != 0x8000:
            result['start'] = [signed(self.read(POOL + 4 + axis * 4)) for axis in range(3)]
            result['velocity'] = [signed(self.read(POOL + 0x1c + axis * 4)) for axis in range(3)]
            result['deadline'] = self.read(POOL + 0x46)
            path = []
            for step in range(1, 41):
                self.write(GAME + 0x38a47, tick + step)
                self.call(0x49b720, [])
                if self.read(POOL + 0x69) & 2 or self.read(GAME + 0x141f3) == 0:
                    break
                path.append([signed(self.read(POOL + 4 + axis * 4)) for axis in range(3)])
            result['path'] = path
        return result


def main():
    units = sys.argv[1:] or ['corthud', 'armham', 'corraid', 'armstump', 'corlevlr', 'armwar']
    executable = Path('local/original/TotalA.exe').read_bytes()
    index = json.loads(Path('local/unit-assets/index.json').read_text())
    cases = []
    for unit in units:
        definition = json.loads((Path('local/unit-assets') / unit / 'unit.json').read_text())['definition']
        weapon = index['weapons'][definition['weapon1'].lower()]
        for case_index, (distance, offset_x, offset_z, rise) in enumerate(
                [(d, dx, dz, r) for d in (128, 192) for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)) for r in (6,)]):
            native = CannonReference(executable, unit)
            native.weapon(weapon['definition'], weapon['runtime'])
            unit_raw = [512 * 65536, 0, 512 * 65536]
            # Host default heading for created and factory-produced units.
            target = [unit_raw[0] + offset_x * distance * 65536, rise * 65536, unit_raw[2] + offset_z * distance * 65536]
            create_state, fire_state, requests = native.engagement(unit_raw, 32768, target, 1000 + case_index)
            outcome = native.shot(create_state, fire_state, unit_raw, 32768, target, 1000 + case_index)
            cases.append(dict(unit=unit, create_state=create_state, fire_state=fire_state, requests=requests, unit_raw=unit_raw,
                              unit_heading=32768, target=target, tick=1000 + case_index, gravity=GRAVITY, expected=outcome))
        print(f'NATIVE_CANNON_LAUNCH {unit}: {sum(1 for c in cases if c["unit"] == unit)} cases; first offset={cases[-1]["expected"]["offset"]} fired={cases[-1]["expected"]["fired"]}', flush=True)
    folder = Path('local/ballistics')
    folder.mkdir(exist_ok=True)
    (folder / 'cannon-launch.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))


if __name__ == '__main__':
    main()
