"""Original factory interpreter playback; synthetic healthy and clear-yard host."""
import json
from pathlib import Path
from native_solar_reference import SolarReference
from native_cob_reference import VTABLE, CALLBACKS, STATES, EXE_HASH
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESP
from cob import signed
from test_cob import fixture


class FactoryReference(SolarReference):
    def __init__(self, executable, cob):
        super().__init__(executable, cob)
        self.shading = {}
        self.caching = {}
        self.argc[3] = 2
        self.write(VTABLE + 12, CALLBACKS + 3 * 0x20)
        self.mu.mem_write(CALLBACKS + 3 * 0x20, b'\xc2\x08\x00')
        self.argc[4] = 2
        self.write(VTABLE + 16, CALLBACKS + 4 * 0x20)
        self.mu.mem_write(CALLBACKS + 4 * 0x20, b'\xc2\x08\x00')

    def callback(self, mu, address, size, data):
        index = (address - CALLBACKS) // 0x20
        sp = mu.reg_read(UC_X86_REG_ESP)
        if index == 3:
            self.caching[str(self.read(sp + 4))] = bool(self.read(sp + 8))
        elif index == 4:
            self.shading[str(self.read(sp + 4))] = bool(self.read(sp + 8))
        elif index == 17 and self.read(sp + 4) == 18:
            mu.reg_write(UC_X86_REG_EAX, self.values.get('18', 0))
        else:
            super().callback(mu, address, size, data)

    def snapshot(self):
        result = super().snapshot()
        result['shading'] = self.shading.copy()
        result['caching'] = self.caching.copy()
        for key, offset in [('spin_targets', 0x34), ('spin_acceleration', 0x40)]:
            result[key] = [[signed(self.read(STATES + i * 0x4c + offset + axis * 4)) for axis in range(3)] for i in range(len(self.pieces))]
        return result


def main():
    folder = Path('local/factory')
    folder.mkdir(exist_ok=True)
    events = {0: 'Create', 31: 'Activate', 160: 'StartBuilding', 230: 'StopBuilding',
              240: 'Deactivate', 260: 'Activate', 280: 'StartBuilding', 360: 'StopBuilding', 370: 'Deactivate'}
    for unit in ['armvp', 'armlab', 'corvp', 'corlab']:
        native = FactoryReference(Path('local/original/TotalA.exe').read_bytes(), Path(f'local/unit-assets/{unit}/script.cob').read_bytes())
        snapshots = []
        for tick in range(751):
            if tick == 30:
                native.read_values[17] = 0
            if tick:
                native.step()
                snapshots.append(dict(tick=tick, action='step', state=native.snapshot()))
            if tick in events:
                native.invoke(events[tick], [])
                snapshots.append(dict(tick=tick, action=events[tick], state=native.snapshot()))
        (folder / f'{unit}-trace.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, unit=unit, snapshots=snapshots)), encoding='utf-8')
        print(f'NATIVE_FACTORY_REFERENCE {unit}: {len(snapshots)} snapshots')
    # Exercise acceleration and integer rounding not covered by the factories' zero-acceleration spins.
    spin_cases = [(0, 5461, 0), (300, 6000, 600), (-300, -6000, -600),
                  (31, 991, 61), (29, 5461, 29), (300, -6000, 600)]
    for case, (acceleration, speed, deceleration) in enumerate(spin_cases):
        words = [0x10021001, acceleration, 0x10021001, speed, 0x10003000, 0, 1,
                 0x10021001, 1000, 0x10013000, 0x10021001, deceleration, 0x10004000, 0, 1,
                 0x10021001, 2000, 0x10013000, 0x10021001, 0, 0x10065000]
        native = FactoryReference(Path('local/original/TotalA.exe').read_bytes(), fixture([word & 0xffffffff for word in words]))
        native.invoke('Create', [])
        snapshots = [dict(tick=0, action='Create', state=native.snapshot())]
        for tick in range(1, 101):
            native.step()
            snapshots.append(dict(tick=tick, action='step', state=native.snapshot()))
        (folder / f'spin{case}-trace.json').write_text(json.dumps(dict(program=native.program, snapshots=snapshots)), encoding='utf-8')
    print(f'NATIVE_SPIN_REFERENCE {len(spin_cases)} cases, 606 snapshots')


if __name__ == '__main__':
    main()
