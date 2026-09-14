"""Original synchronous Killed(severity, corpsetype) script calls through 0x4b0bc0, recording debris callbacks."""
import json
import struct
from pathlib import Path
from native_factory_reference import FactoryReference
from native_cob_reference import EXE_HASH, SCRIPT, CALLBACKS, VTABLE
from unicorn.x86_const import UC_X86_REG_ESP
from cob import signed

NAME, LOCALS = 0x13f0000, 0x13f0100
UNITS = ['armflash', 'armstump', 'armpw', 'armrock', 'armham', 'armjeth', 'armwar', 'armsam', 'armfav', 'armcv', 'armck', 'armmlv',
         'corraid', 'corthud', 'corlevlr', 'corstorm', 'cormist', 'corcrash', 'corfav', 'corgator', 'corak', 'corcv', 'corck', 'cormlv',
         'armsolar', 'armvp', 'armlab', 'corsolar', 'corvp', 'corlab', 'armmex', 'cormex']
SEVERITIES = [1, 10, 24, 25, 26, 49, 50, 51, 75, 99, 100]


class KilledReference(FactoryReference):
    def __init__(self, executable, cob):
        super().__init__(executable, cob)
        self.explosions = []

    def callback(self, mu, address, size, data):
        index = (address - CALLBACKS) // 0x20
        if index == self.explode_index:
            sp = mu.reg_read(UC_X86_REG_ESP)
            self.explosions.append([signed(self.read(sp + 4 + i * 4)) for i in range(self.argc[index])])
            return
        super().callback(mu, address, size, data)


def main():
    executable = Path('local/original/TotalA.exe').read_bytes()
    # Interpreter opcode 0x10071000 (EXPLODE) calls engine vtable offset 0x34 with (piece, flags).
    explode_index = 13
    cases = []
    for unit in UNITS:
        cob = Path(f'local/unit-assets/{unit}/script.cob').read_bytes()
        program = json.loads(Path(f'local/unit-assets/{unit}/script.json').read_text())
        if 'Killed' not in [function['name'] for function in program['functions']]:
            continue
        for severity in SEVERITIES:
            native = KilledReference(executable, cob)
            native.explode_index = explode_index
            if explode_index is not None:
                native.argc[explode_index] = 2
                native.write(VTABLE + explode_index * 4, CALLBACKS + explode_index * 0x20)
                native.mu.mem_write(CALLBACKS + explode_index * 0x20, b'\xc2\x08\x00')
            native.invoke('Create', [])
            # Name-based calls need the loader's relocated function and piece name tables.
            for table_offset, count in [(0x1c, len(program['functions'])), (0x20, len(program['pieces']))]:
                table = native.read(SCRIPT + table_offset)
                for index in range(count):
                    native.write(table + index * 4, SCRIPT + native.read(table + index * 4))
            native.mu.mem_write(NAME, b'Killed\0')
            native.write(LOCALS, severity)
            native.write(LOCALS + 4, 0)
            native.call(0x4b0bc0, [NAME, LOCALS, LOCALS + 4, 0, 0])
            cases.append(dict(unit=unit, severity=severity, corpsetype=signed(native.read(LOCALS + 4)),
                              severity_out=signed(native.read(LOCALS)), explosions=native.explosions,
                              hidden=[index for index, piece in enumerate(native.snapshot()['pieces']) if not piece.get('visible', True)]))
        print(f'NATIVE_KILLED {unit}: corpse types {[c["corpsetype"] for c in cases if c["unit"] == unit]}', flush=True)
    folder = Path('local/killed')
    folder.mkdir(exist_ok=True)
    (folder / 'native-trace.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))


if __name__ == '__main__':
    main()
