"""Full original settlement with supplied renewable generator/environment fields."""
import json
import struct
from pathlib import Path
from native_movement_reference import MovementReference, UNIT, DEFINITION, GAME
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    player, external = 0x1010000, 0x1011000
    def put(address, value):
        native.mu.mem_write(address, struct.pack('<f', value))
    cases = []
    for wind, tidal, extracts, makes in [(1, 0, 0, 0), (0, 20, 0, 0), (2, 20, 0, 0), (2, 20, 0.001, 0), (2, 20, 0, 1), (-1, 20, 0, 0)]:
        for strength in [0, 0.1, 0.5, 1.75, 20]:
            for active in [False, True]:
                for debt in [0, 60]:
                    native.mu.mem_write(player, bytes(0x200))
                    native.mu.mem_write(external, bytes(0x40))
                    native.mu.mem_write(UNIT, bytes(0x118))
                    native.mu.mem_write(DEFINITION, bytes(0x300))
                    native.write(player, 1)
                    native.mu.mem_write(player + 0x73, b'\x03')
                    native.write(player + 0x67, UNIT)
                    native.write(player + 0x6b, UNIT)
                    native.write(player + 0xec, external)
                    native.write(UNIT + 0x92, DEFINITION)
                    native.write(UNIT + 0xec, player)
                    native.write(UNIT + 0x110, 0x30000000)
                    native.mu.mem_write(UNIT + 0x10e, bytes([int(active)]))
                    for offset, value in [(0x1d2, wind), (0x1d6, tidal), (0x1ce, extracts), (0x1e2, 1000)]:
                        put(DEFINITION + offset, value)
                    native.mu.mem_write(DEFINITION + 0x22d, bytes([makes]))
                    put(UNIT + 0xbc, 3.5)
                    put(UNIT + 0xc8, debt)
                    put(GAME + 0x37ede, strength)
                    put(GAME + 0x14267, strength)
                    native.call(0x401360, [player])
                    result = struct.unpack('<f', native.mu.mem_read(UNIT + 0xcc, 4))[0]
                    cases.append(dict(wind=wind, tidal=tidal, extracts=extracts, makes=makes, strength=strength, active=active, debt=debt, income=3.5, expected=result))
    Path('local/metal-maker/renewable.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_RENEWABLE_ENERGY {len(cases)} cases')


if __name__ == '__main__':
    main()
