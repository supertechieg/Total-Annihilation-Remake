"""Original solar COB playback with explicit health/build-percent host inputs."""
import json
from pathlib import Path
from native_cob_reference import NativeReference, EXE_HASH, VTABLE, CALLBACKS
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESP


class SolarReference(NativeReference):
    def __init__(self, executable, cob):
        super().__init__(executable, cob)
        self.read_values = {4: 100, 17: 100}
        self.argc[17] = 5
        self.write(VTABLE + 17 * 4, CALLBACKS + 17 * 0x20)
        self.mu.mem_write(CALLBACKS + 17 * 0x20, b'\xc2\x14\x00')

    def callback(self, mu, address, size, data):
        if (address - CALLBACKS) // 0x20 == 17:
            key = self.read(mu.reg_read(UC_X86_REG_ESP) + 4)
            if key not in self.read_values:
                raise ValueError(f'Unknown solar read: {key}')
            mu.reg_write(UC_X86_REG_EAX, self.read_values[key])
        else:
            super().callback(mu, address, size, data)


def main():
    native = SolarReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/unit-assets/armsolar/script.cob').read_bytes())
    events = {0: 'Create', 31: 'Activate', 180: 'Deactivate', 190: 'Activate', 350: 'Deactivate', 440: 'Activate'}
    snapshots = []
    for tick in range(601):
        if tick == 30:
            native.read_values[17] = 0
        if tick:
            native.step()
            snapshots.append(dict(tick=tick, action='step', state=native.snapshot()))
        if tick in events:
            native.invoke(events[tick], [])
            snapshots.append(dict(tick=tick, action=events[tick], state=native.snapshot()))
    folder = Path('local/solar')
    folder.mkdir(exist_ok=True)
    (folder / 'native-trace.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, snapshots=snapshots)), encoding='utf-8')
    print(f'NATIVE_SOLAR_REFERENCE {len(snapshots)} snapshots')


if __name__ == '__main__':
    main()
