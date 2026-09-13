"""Record original ballistic launch-angle decisions at 0x49a890."""
import json
from pathlib import Path
import random
import struct
from native_movement_reference import MovementReference, GAME
from native_cob_reference import EXE_HASH


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    rng = random.Random(1949)
    cases = []
    for index in range(1200):
        delta = [rng.randrange(-300, 301) * 65536, rng.randrange(-60, 61) * 65536, rng.randrange(-300, 301) * 65536]
        speed = [371370, 655359, 218453, 1000000][index % 4]
        gravity = [8155, 4000, 16000][index % 3]
        minimum = [-1.0, 0.0, 0.1, 0.3, 0.7][index % 5]
        native.write(GAME + 0x14263, gravity)
        bits = struct.unpack('<I', struct.pack('<f', minimum))[0]
        result = native.call(0x49a890, [*delta, speed, bits]) & 0xffff
        cases.append(dict(delta=delta, speed=speed, gravity=gravity, minimum=struct.unpack('<f', struct.pack('<I', bits))[0], expected=result))
    for distance in [0, 1, 128 * 65536, 240 * 65536, 371370 * 371370 // 8155, 371370 * 371370 // 8155 + 1]:
        for height in [-32 * 65536, 0, 32 * 65536]:
            for minimum in [0.0, 0.7853981633974475]:
                delta = [distance, height, 0]
                native.write(GAME + 0x14263, 8155)
                bits = struct.unpack('<I', struct.pack('<f', minimum))[0]
                result = native.call(0x49a890, [*delta, 371370, bits]) & 0xffff
                cases.append(dict(delta=delta, speed=371370, gravity=8155, minimum=struct.unpack('<f', struct.pack('<I', bits))[0], expected=result))
    folder = Path('local/ballistics')
    folder.mkdir(exist_ok=True)
    (folder / 'native-aim.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)), encoding='utf-8')
    print(f'NATIVE_BALLISTIC_AIM {len(cases)} cases, {sum(c["expected"] != 32768 for c in cases)} accepted')


if __name__ == '__main__':
    main()
