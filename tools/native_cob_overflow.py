"""Original interpreter behaviour when all eight COB thread slots are busy.

Host starts through 0x4b0b00 return 0, START_SCRIPT (0x4b18c2) and CALL_SCRIPT (0x4b192f) skip the start and
leave their arguments on the caller's stack; a dropped CALL_SCRIPT still blocks with wait slot -1 until a signal.
Also exercises RAND with a seeded shared RNG and EMIT_SFX. Writes local/scripts/native-overflow-trace.json.
"""
import json
from pathlib import Path
import struct
from native_cob_reference import NativeReference, CONTEXT, EXE_HASH
from cob import signed

PUSH, SLEEP, RETURN = 0x10021001, 0x10013000, 0x10065000
START, CALL, MASK, SIGNAL = 0x10061000, 0x10062000, 0x10068000, 0x10067000
RAND, EMIT_SFX, POP_STATIC = 0x10041000, 0x1000F000, 0x10023004

FUNCTIONS = [
    ('sleep', [PUSH, 1000, SLEEP, PUSH, 0, RETURN]),
    ('late_starter', [PUSH, 100, SLEEP, PUSH, 11, PUSH, 22, START, 0, 2, PUSH, 1000, SLEEP, PUSH, 0, RETURN]),
    ('late_caller', [PUSH, 2, MASK, PUSH, 100, SLEEP, PUSH, 33, CALL, 0, 1, PUSH, 5, RETURN]),
    ('signaller', [PUSH, 2, SIGNAL, PUSH, 0, RETURN]),
    ('smoke', [PUSH, 1, PUSH, 66, RAND, POP_STATIC, 0, PUSH, 3, PUSH, 3, RAND, POP_STATIC, 1,
               PUSH, 257, EMIT_SFX, 1, PUSH, 100, SLEEP, PUSH, 0, RETURN]),
]
SCENARIO = {0: ['sleep'] * 6 + ['late_starter', 'late_caller', 'sleep'], 2: ['smoke'], 50: ['signaller'], 51: ['smoke', 'sleep']}
SEED_INPUT = 0x51fc88


def build():
    words = []
    addresses = []
    for _name, code in FUNCTIONS:
        addresses.append(len(words))
        words += code
    names = [name for name, _ in FUNCTIONS] + ['body', 'flare']
    nf, np = len(FUNCTIONS), 2
    code_at = 44
    function_at = code_at + 4 * len(words)
    name_at = function_at + 4 * nf
    piece_at = name_at + 4 * nf
    strings = piece_at + 4 * np
    offsets = []
    blob = b''
    for name in names:
        offsets.append(strings + len(blob))
        blob += name.encode() + b'\0'
    header = struct.pack('<11I', 4, nf, np, len(words), 2, 0, function_at, name_at, piece_at, code_at, strings)
    return (header + struct.pack(f'<{len(words)}I', *[w & 0xffffffff for w in words])
            + struct.pack(f'<{nf}I', *addresses) + struct.pack(f'<{nf + np}I', *offsets) + blob)


def slots(native):
    result = []
    for i in range(8):
        base = CONTEXT + 0x1c + i * 0xa4
        state = native.read(base)
        if state:
            entry = dict(slot=i, pc=native.read(base + 4), sp=signed(native.read(base + 8)),
                         stack=[signed(native.read(base + 0x24 + 4 * k)) for k in range(4)], state=hex(state))
            if state & 0xfff00000 == 0x2800000:
                entry['wait_slot'] = signed(native.read(base + 0x18))
            result.append(entry)
    return result


def main():
    cob = build()
    native = NativeReference(Path('local/original/TotalA.exe').read_bytes(), cob)
    native.seed(SEED_INPUT)
    seed_start = native.rng_seed()
    snapshots = []
    for tick in range(61):
        if tick:
            native.step()
            snapshots.append(dict(tick=tick, action='step', started=True, slots=slots(native),
                                  statics=[signed(native.read(0x1300000 + 4 * i)) for i in range(2)]))
        for name in SCENARIO.get(tick, []):
            started = native.invoke(name, [])
            snapshots.append(dict(tick=tick, action=name, started=started, slots=slots(native),
                                  statics=[signed(native.read(0x1300000 + 4 * i)) for i in range(2)]))
    output = Path('local/scripts/native-overflow-trace.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dict(exe_sha256=EXE_HASH, program=native.program, snapshots=snapshots, seed_start=seed_start,
                                      seed_end=native.rng_seed(), sfx=native.sfx, dropped=native.dropped)), encoding='utf-8')
    print(f'NATIVE_COB_OVERFLOW {len(snapshots)} snapshots; dropped host starts={native.dropped}; sfx={native.sfx}; seed {seed_start:#x} -> {native.rng_seed():#x}')


if __name__ == '__main__':
    main()
