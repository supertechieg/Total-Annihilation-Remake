"""Execute original positive construction progress and resource request routines.

Synthetic builder/target records omit live-unit flags, so completion lifecycle
side effects are intentionally outside this oracle. No game startup runs.
"""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, EXE_HASH

BUILDER = 0x1010000
TARGET = 0x1011000
DEFINITION = 0x1012000


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


class ConstructionReference(MovementReference):
    def floating(self, address):
        return struct.unpack('<f', self.mu.mem_read(address, 4))[0]

    def step_build(self, data):
        self.mu.mem_write(BUILDER, bytes(0x118))
        self.mu.mem_write(TARGET, bytes(0x118))
        self.write(TARGET + 0x92, DEFINITION)
        for offset, key in [(0x186, 'energy_cost'), (0x18a, 'metal_cost')]:
            self.write(DEFINITION + offset, bits(data[key]))
        self.write(DEFINITION + 0x1ea, data['build_time'])
        self.write(DEFINITION + 0x1fa, data['max_health'])
        self.write(TARGET + 0x104, bits(data['remaining']))
        self.short(TARGET + 0x108, data['health'])
        for offset, key in [(0xc8, 'energy_debt'), (0xe0, 'metal_debt')]:
            self.write(BUILDER + offset, bits(data[key]))
        accepted = self.call(0x41ba60, [BUILDER, TARGET, bits(data['work'])], timeout=0)
        return dict(accepted=bool(accepted), remaining=self.floating(TARGET + 0x104),
                    health=struct.unpack('<h', self.mu.mem_read(TARGET + 0x108, 2))[0],
                    energy_requested=self.floating(BUILDER + 0xc0), metal_requested=self.floating(BUILDER + 0xd8),
                    energy_accepted=self.floating(BUILDER + 0xc4), metal_accepted=self.floating(BUILDER + 0xdc))


def main():
    native = ConstructionReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    rng = random.Random(419860)
    cases = []
    for i in range(1000):
        data = dict(energy_cost=rng.randrange(50000), metal_cost=rng.randrange(5000),
                    build_time=rng.randrange(1, 100000), max_health=rng.randrange(1, 30000),
                    remaining=rng.choice([0.0, 1.0, rng.random()]), health=rng.randrange(1, 500),
                    energy_debt=rng.choice([0.0, 0.1, -1.0]), metal_debt=rng.choice([0.0, 0.1, -1.0]),
                    work=rng.choice([0.0, 10.0, 300.0, 100000.0]))
        data['remaining'] = struct.unpack('<f', struct.pack('<f', data['remaining']))[0]
        cases.append(dict(input=data, expected=native.step_build(data)))
    folder = Path('local/construction')
    folder.mkdir(exist_ok=True)
    (folder / 'native-trace.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_CONSTRUCTION_REFERENCE {len(cases)} cases')


if __name__ == '__main__':
    main()
