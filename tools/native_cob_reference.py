"""Execute the original x86 COB interpreter in Unicorn with pose-only host callbacks.

No Windows/game startup is executed. This is a version-pinned test oracle, not an engine.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'local/python-deps'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ECX, UC_X86_REG_EIP, UC_X86_REG_ESP
from cob import decode, signed
from inspect_install import inspect_pe

EXE_HASH = '3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e'
CONTEXT = 0x1000000
VTABLE = 0x1001000
CALLBACKS = 0x1002000
STOP = 0x100f000
SCRIPT = 0x1100000
STATES = 0x1200000
STATICS = 0x1300000
STACK_TOP = 0x13ff000

SCENARIO = {
    0: [('Create', [])],
    1: [('StartMoving', [])],
    20: [('AimPrimary', [8192, 0])],
    60: [('FirePrimary', [])],
    65: [('StopMoving', [])],
    100: [('TargetCleared', [0])],
    150: [('AimPrimary', [16000, 0])],
    151: [('AimTertiary', [-8192, 0])],
    200: [('FireTertiary', [])],
    205: [('TargetCleared', [0])],
    250: [('StartBuilding', [4096, 0])],
    290: [('StopBuilding', [])],
    330: [('StartMoving', [])],
    380: [('StopMoving', [])],
}


class NativeReference:
    def __init__(self, executable, cob):
        if hashlib.sha256(executable).hexdigest() != EXE_HASH:
            raise ValueError('This oracle only supports the recorded executable SHA-256')
        self.program = decode(cob)
        self.mu = Uc(UC_ARCH_X86, UC_MODE_32)
        self.mu.mem_map(0x400000, 0x200000)
        self.mu.mem_map(CONTEXT, 0x400000)
        self.mu.mem_write(0x400000, executable[:1024])
        for section in inspect_pe(executable)['sections']:
            self.mu.mem_write(0x400000 + section['rva'], executable[section['raw_offset']:section['raw_offset'] + section['raw_size']])
        self.mu.mem_write(SCRIPT, cob)
        # TA's loader relocates these directory/code offsets into pointers.
        for offset in (0x18, 0x1c, 0x20, 0x24):
            self.write(SCRIPT + offset, SCRIPT + self.read(SCRIPT + offset))
        self.write(CONTEXT, VTABLE)
        self.write(CONTEXT + 4, 30)
        self.write(CONTEXT + 8, SCRIPT)
        self.write(CONTEXT + 0x10, STATICS)
        self.write(CONTEXT + 0x14, STATES)
        self.pieces = [dict(name=name, position=[0, 0, 0], rotation=[0, 0, 0], visible=True) for name in self.program['pieces']]
        self.values = {}
        self.callback_counts = {}
        # Callback argument counts: set/get transform, visibility, and SET_VALUE.
        self.argc = {0: 3, 1: 3, 2: 2, 5: 2, 6: 2, 16: 2}
        for index, count in self.argc.items():
            address = CALLBACKS + index * 0x20
            self.write(VTABLE + index * 4, address)
            self.mu.mem_write(address, b'\xc2' + struct.pack('<H', count * 4))
        self.mu.hook_add(UC_HOOK_CODE, self.callback, begin=CALLBACKS, end=CALLBACKS + 0x400)

    def read(self, address):
        return struct.unpack('<I', self.mu.mem_read(address, 4))[0]

    def write(self, address, value):
        self.mu.mem_write(address, struct.pack('<I', value & 0xffffffff))

    def callback(self, mu, address, size, _):
        index = (address - CALLBACKS) // 0x20
        if index not in self.argc:
            raise RuntimeError(f'Unexpected engine callback {index}')
        self.callback_counts[index] = self.callback_counts.get(index, 0) + 1
        sp = mu.reg_read(UC_X86_REG_ESP)
        args = [signed(self.read(sp + 4 + i * 4)) for i in range(self.argc[index])]
        if index in (0, 1):
            piece, axis, value = args
            self.pieces[piece]['position' if index == 0 else 'rotation'][axis] = value
        elif index == 2:
            self.pieces[args[0]]['visible'] = bool(args[1])
        elif index in (5, 6):
            value = self.pieces[args[0]]['position' if index == 5 else 'rotation'][args[1]]
            mu.reg_write(UC_X86_REG_EAX, value & 0xffffffff)
        elif index == 16:
            self.values[str(args[0])] = args[1]

    def call(self, address, args, this=CONTEXT, timeout=1000000):
        sp = STACK_TOP - (len(args) + 1) * 4
        self.write(sp, STOP)
        for i, value in enumerate(args):
            self.write(sp + 4 + i * 4, value)
        self.mu.reg_write(UC_X86_REG_ESP, sp)
        self.mu.reg_write(UC_X86_REG_ECX, this)
        self.mu.emu_start(address, STOP, timeout=timeout, count=2000000)
        if self.mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError('Native interpreter failed to return within execution limit')
        return self.mu.reg_read(UC_X86_REG_EAX)

    def invoke(self, name, args):
        index = next(i for i, f in enumerate(self.program['functions']) if f['name'] == name)
        # Original host invocation helper: callback=null, run immediately, initial SP=-1.
        result = self.call(0x4b0b00, [index, 0, 1, 0, *(args + [0] * (4 - len(args)))])
        if result != 1:
            raise RuntimeError('Original host callback failed to allocate a slot')

    def step(self):
        self.call(0x4b0d60, [1])

    def snapshot(self):
        states = {0x1000000: 'ready', 0x2100000: 'turn', 0x2200000: 'move', 0x2400000: 'sleep', 0x2800000: 'call'}
        threads = []
        for i in range(8):
            base = CONTEXT + 0x1c + i * 0xa4
            state = self.read(base)
            if state:
                threads.append(dict(slot=i, pc=self.read(base + 4), state=states.get(state, hex(state))))
        pieces = json.loads(json.dumps(self.pieces))
        for i, piece in enumerate(pieces):
            for key, offset in [('move_target', 4), ('turn_target', 0x1c), ('move_speed', 0x10), ('turn_speed', 0x28)]:
                piece[key] = [signed(self.read(STATES + i * 0x4c + offset + axis * 4)) for axis in range(3)]
        return dict(statics=[signed(self.read(STATICS + i * 4)) for i in range(self.program['static_count'])],
                    pieces=pieces, values=self.values.copy(), threads=threads)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=Path('local/original/TotalA.exe'))
    parser.add_argument('--cob', type=Path, default=Path('local/viewer-assets/armcom.cob'))
    parser.add_argument('--output', type=Path, default=Path('local/scripts/native-trace.json'))
    args = parser.parse_args()
    reference = NativeReference(args.exe.read_bytes(), args.cob.read_bytes())
    snapshots = []
    for tick in range(451):
        if tick:
            reference.step()
            snapshots.append(dict(label=f'{tick}:step', state=reference.snapshot()))
        for index, (name, parameters) in enumerate(SCENARIO.get(tick, [])):
            reference.invoke(name, parameters)
            snapshots.append(dict(label=f'{tick}:{name}:{index}', state=reference.snapshot()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(exe_sha256=EXE_HASH, cob_sha256=reference.program['sha256'],
                         scenario=SCENARIO, snapshots=snapshots), indent=2), encoding='utf-8')
    print(json.dumps(dict(snapshots=len(snapshots), callbacks=reference.callback_counts, output=str(args.output)), indent=2))


if __name__ == '__main__':
    main()
