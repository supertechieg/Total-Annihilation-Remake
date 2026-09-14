"""Execute original numeric weapon-loader conversions, including its text parser."""
import json
from pathlib import Path
import struct
from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH
from unicorn.x86_const import UC_X86_REG_EBP


class WeaponReference(MovementReference):
    def angle(self, value):
        stub, string, output = 0x1008000, 0x1009000, 0x100a000
        self.mu.mem_write(string, str(value).encode('ascii') + b'\0')
        code = b'\x68' + struct.pack('<I', string)
        code += b'\xe8' + struct.pack('<i', 0x4e4560 - (stub + len(code) + 5))
        code += b'\x83\xc4\x04'
        code += b'\xe9' + struct.pack('<i', 0x42e729 - (stub + len(code) + 5))
        self.mu.mem_write(stub, code)
        # Skip argument pushes for the next unrelated field. Preserve original
        # FMUL and float32 FSTP instructions.
        self.mu.mem_write(0x42e72f, b'\xe9' + struct.pack('<i', 0x42e738 - 0x42e734))
        self.mu.mem_write(0x42e73e, b'\xc3')
        self.mu.ctl_remove_cache(stub, stub + len(code))
        self.mu.ctl_remove_cache(0x42e729, 0x42e73f)
        self.mu.reg_write(UC_X86_REG_EBP, output)
        self.call(stub, [])
        return struct.unpack('<f', self.mu.mem_read(output + 0xc8, 4))[0]

    def convert(self, value, kind):
        entry, end = {'velocity': (0x42e4c6, 0x42e4d1), 'reload': (0x42e54b, 0x42e556),
                      'burst_rate': (0x42e645, 0x42e650), 'duration': (0x42e67c, 0x42e687),
                      'start_velocity': (0x42e4e4, 0x42e4ef), 'acceleration': (0x42e502, 0x42e50d), 'turn_rate': (0x42e60e, 0x42e619)}[kind]
        stub, string = 0x1008000, 0x1009000
        self.mu.mem_write(string, str(value).encode('ascii') + b'\0')
        code = b'\x68' + struct.pack('<I', string)
        code += b'\xe8' + struct.pack('<i', 0x4e4560 - (stub + len(code) + 5))
        code += b'\x83\xc4\x04'
        code += b'\xe9' + struct.pack('<i', entry - (stub + len(code) + 5))
        self.mu.mem_write(stub, code)
        self.mu.mem_write(end, b'\xc3')
        self.mu.ctl_remove_cache(stub, stub + len(code))
        self.mu.ctl_remove_cache(entry, end + 1)
        result = self.call(stub, [])
        if kind in ('reload', 'burst_rate', 'turn_rate', 'duration'):
            result &= 0xffff  # Original loader stores AX into the weapon record.
        elif result >= 0x80000000:
            result -= 0x100000000
        return result


def main():
    native = WeaponReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    index = json.loads(Path('local/unit-assets/index.json').read_text())
    cases = []
    for weapon, item in index['weapons'].items():
        for kind, field in [('velocity', 'weaponvelocity'), ('start_velocity', 'startvelocity'), ('acceleration', 'weaponacceleration'), ('reload', 'reloadtime'), ('burst_rate', 'burstrate'), ('turn_rate', 'turnrate'), ('duration', 'duration')]:
            value = item['definition'].get(field, '0')
            cases.append(dict(weapon=weapon, kind=kind, value=value, result=native.convert(value, kind)))
    for value in ['0', '.1', '.2', '.3', '.4', '1.1', '1.2', '29.999', '30', '300', '-.1', '-.3', '.03333333333333333']:
        for kind in ['velocity', 'start_velocity', 'acceleration', 'reload', 'burst_rate', 'turn_rate', 'duration']:
            cases.append(dict(weapon='synthetic', kind=kind, value=value, result=native.convert(value, kind)))
    for weapon, item in index['weapons'].items():
        value = item['definition'].get('minbarrelangle', '-11.25')
        cases.append(dict(weapon=weapon, kind='minimum_angle', value=value, result=native.angle(value)))
    for value in ['-90', '-45', '-11.25', '-.1', '0', '.1', '11.25', '45', '90', '180']:
        cases.append(dict(weapon='synthetic', kind='minimum_angle', value=value, result=native.angle(value)))
    folder = Path('local/weapons')
    folder.mkdir(exist_ok=True)
    (folder / 'native-conversions.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_WEAPON_CONVERSIONS {len(cases)} cases')
    print([item for item in cases if item['weapon'] == 'emg'])


if __name__ == '__main__':
    main()
