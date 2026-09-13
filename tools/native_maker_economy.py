"""Full original settlement for a generator and two makers over shortages/recovery.

Player type 3 bypasses the unrelated cloak callback; no economy instructions patched.
"""
import json
import argparse
import struct
from pathlib import Path
from native_movement_reference import MovementReference, UNIT, DEFINITION
from native_cob_reference import EXE_HASH


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--remove-maker', action='store_true')
    remove_maker = parser.parse_args().remove_maker
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    player, external = 0x1010000, 0x1011000
    def put(address, value):
        native.mu.mem_write(address, struct.pack('<f', value))
    def read(address):
        return struct.unpack('<f', native.mu.mem_read(address, 4))[0]
    cases = []
    for stock in [0, 30, 60, 120, 1000]:
        native.mu.mem_write(player, bytes(0x200))
        native.mu.mem_write(external, bytes(0x40))
        native.write(player, 1)
        native.mu.mem_write(player + 0x73, b'\x03')
        native.write(player + 0x67, UNIT)
        native.write(player + 0x6b, UNIT + 2 * 0x118)
        native.write(player + 0xec, external)
        put(player + 0x8c, stock)
        for i in range(3):
            unit, definition = UNIT + i * 0x118, DEFINITION + i * 0x300
            native.mu.mem_write(unit, bytes(0x118))
            native.mu.mem_write(definition, bytes(0x300))
            native.write(unit + 0x92, definition)
            native.write(unit + 0xec, player)
            native.write(unit + 0x110, 0x30000000)
            native.mu.mem_write(unit + 0x10e, b'\x01')
            put(definition + 0x1c6, 60 if i else 0)
            native.mu.mem_write(definition + 0x22d, bytes([1 if i else 0]))
            put(definition + 0x1e2, 1000 if i == 0 else 0)
            put(definition + 0x1e6, 1000 if i == 0 else 0)
        snapshots = []
        for period in range(16):
            if remove_maker and period == 6:
                native.write(UNIT + 0x118 + 0x110, 0x20000000)
            income = 20 if period < 8 else 200
            put(DEFINITION + 0x1c2, income)
            # Toggle one maker during recovery; the other remains active.
            active = period not in [10, 11]
            native.mu.mem_write(UNIT + 0x118 + 0x10e, bytes([int(active)]))
            native.call(0x401360, [player])
            snapshots.append(dict(income=income, active=active, removed=remove_maker and period >= 6, energy=read(player + 0x8c), metal=read(player + 0x98),
                                  energy_income=read(player + 0x90), energy_requested=read(player + 0x94),
                                  metal_income=read(player + 0x9c),
                                  debts=[read(UNIT + i * 0x118 + 0xc8) for i in range(3)]))
        cases.append(dict(stock=stock, snapshots=snapshots))
    filename = 'economy-removal.json' if remove_maker else 'economy.json'
    Path('local/metal-maker', filename).write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_MAKER_ECONOMY {len(cases) * 16} snapshots')


if __name__ == '__main__':
    main()
