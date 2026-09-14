"""Execute the original LOS ray-table loader 0x433130 (-> 0x433380 -> 0x4336f0) on gamedata/los.tdf.

Everything from TDF text to the ray object at 0x51e6a0 runs unmodified: the TDF text parser (comment strip
0x4c33a0, tree builder 0x4c3e40), section enter 0x4c3410, int getter 0x4c46c0, string getter 0x4c48c0, the
CRT strtok 0x4e5280 / atoi 0x4e4f70 / sprintf 0x4e42b0, the vector code and the accessor 0x433500.

Replaced boundaries (each is a host service, not LOS logic):
  * 0x4290f0 path builder: probes the HPI/game file system (0x49f580, 0x4bb0f0, 0x4bb5b0); the stub writes
    "gamedata\\los.TDF" into the caller's buffer (stdcall, ret 0x10). The path is only a file-open name.
  * 0x4c2f60 TDF file load (open 0x4bb5b0, size 0x4bbd00, read 0x4bb7c0 through the HPI layer): replaced by a
    trampoline into the original in-memory variant 0x4c3120(buffer, length, 0, name), which performs the same
    copy + 0x4c33a0 + 0x4c3e40 sequence as the file variant after its read. Returns 1 like a successful load.
  * Heap: operator new 0x4d8660, delete 0x4d8670, game malloc 0x4d83c0, game free 0x4d85b0,
    CRT malloc 0x4e8890, CRT free 0x4e8820 (used by the TDF string class 0x4c91b0) -> Python bump allocator
    (the Win32 heap imports are not available without process start-up; memory is never reused).
  * _getptd 0x4eb0f0 (TlsGetValue/calloc) -> one zeroed per-thread data block; only strtok's saved token
    pointer lives there for this path.
Every Win32 import slot is redirected to a trap that aborts the case, so any unexpected OS call is reported.

Fault records (compare_native_los_tables.gd classifies them):
  * fatal: the TDF parse-error handler 0x4b6290 (MessageBox + exit) was entered; its message is recorded and the
    case stops there. Before this hook existed the handler crashed on the unset window global 0x51fbd0.
  * first_out_of_range_ray: the first 0x4336f0 call whose ray object lies outside the table's ray vector (int16
    ray index wrap in 0x433380). A load that completes after such a call is still reported as a fault.
  * last_line_call: the (table, line, rotation) of the last 0x4336f0 call before the fault.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH, UC_HOOK_CODE, STOP, STACK_TOP
from unicorn import UcError
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ECX, UC_X86_REG_EDI
from cob import signed

RAYS = 0x51e6a0
HEAP = 0x2000000
HEAP_SIZE = 0x1000000
TEXT = 0x3000000
PTD = 0x3100000
TRAP = 0x3200000
# Win32 critical sections guard CRT/file/locale state against other threads; this oracle is single-threaded,
# so entering/leaving is a no-op with no observable effect (stdcall, one pointer argument).
BENIGN_IMPORTS = {'KERNEL32.dll!EnterCriticalSection': 4, 'KERNEL32.dll!LeaveCriticalSection': 4}


class LosLoader:
    def __init__(self, executable, cob):
        self.native = native = MovementReference(executable, cob)
        mu = native.mu
        mu.mem_map(HEAP, HEAP_SIZE)
        mu.mem_map(TEXT, 0x100000)
        mu.mem_map(PTD, 0x1000)
        mu.mem_map(TRAP, 0x10000)
        self.cursor = HEAP
        self.trap_names = {}
        self.trapped = []
        self.benign = {}
        self.ray_calls = []
        self.first_out_of_range = None
        self.fatal = None
        self._redirect_imports(executable)
        mu.hook_add(UC_HOOK_CODE, self._fatal, begin=0x4b6290, end=0x4b6290)
        mu.hook_add(UC_HOOK_CODE, self._trap, begin=TRAP, end=TRAP + 0xffff)
        # allocators: cdecl
        for address, argument in [(0x4d8660, 4), (0x4d83c0, 4), (0x4e8890, 4)]:
            mu.mem_write(address, b'\xc3')
            mu.hook_add(UC_HOOK_CODE, self._alloc, begin=address, end=address, user_data=argument)
        for address in (0x4d8670, 0x4d85b0, 0x4e8820):
            mu.mem_write(address, b'\xc3')
        mu.mem_write(0x4eb0f0, b'\xb8' + struct.pack('<I', PTD) + b'\xc3')
        mu.mem_write(0x4290f0, b'\xc2\x10\x00')
        mu.hook_add(UC_HOOK_CODE, self._path, begin=0x4290f0, end=0x4290f0)
        mu.hook_add(UC_HOOK_CODE, self._ray_call, begin=0x4336f0, end=0x4336f0)
        # Observation only: the line string 0x4c48c0 copied into 0x4336f0's buffer (esp+0x34), or None if absent.
        self.line_values = []
        mu.hook_add(UC_HOOK_CODE, self._line_value, begin=0x433738, end=0x433738)

    def _redirect_imports(self, data):
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        base = struct.unpack_from('<I', data, pe + 52)[0]
        mu = self.native.mu
        rva = struct.unpack_from('<I', data, pe + 24 + 104)[0]
        descriptor = base + rva
        slot_index = 0
        while True:
            first_thunk, name_rva = self.native.read(descriptor + 16), self.native.read(descriptor + 12)
            if not first_thunk:
                break
            dll = bytes(mu.mem_read(base + name_rva, 64)).split(b'\0')[0].decode()
            slot = base + first_thunk
            while True:
                value = self.native.read(slot)
                if not value:
                    break
                name = f'#{value & 0xffff}' if value & 0x80000000 else bytes(mu.mem_read(base + value + 2, 64)).split(b'\0')[0].decode()
                stub = TRAP + slot_index * 4
                mu.mem_write(stub, b'\xcc')
                self.trap_names[stub] = f'{dll}!{name}'
                self.native.write(slot, stub)
                slot += 4
                slot_index += 1
            descriptor += 20

    def _trap(self, mu, address, size, data):
        name = self.trap_names.get(address, hex(address))
        sp = mu.reg_read(UC_X86_REG_ESP)
        if name in BENIGN_IMPORTS:
            self.benign[name] = self.benign.get(name, 0) + 1
            mu.reg_write(UC_X86_REG_ESP, sp + 4 + BENIGN_IMPORTS[name])
            mu.reg_write(UC_X86_REG_EIP, self.native.read(sp))
            return
        stack = struct.unpack('<128I', mu.mem_read(sp, 512))
        self.trapped.append(dict(name=name, return_address=hex(stack[0]),
                                 stack_code_addresses=[hex(v) for v in stack if 0x401000 <= v < 0x4fc000][:12]))
        mu.emu_stop()

    def _alloc(self, mu, address, size, argument):
        count = self.native.read(mu.reg_read(UC_X86_REG_ESP) + argument)
        pointer = self.cursor
        self.cursor = (self.cursor + max(count, 1) + 15) & ~7
        if self.cursor >= HEAP + HEAP_SIZE:
            raise MemoryError('bump heap exhausted')
        mu.reg_write(UC_X86_REG_EAX, pointer)

    def _path(self, mu, address, size, data):
        buffer = self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        mu.mem_write(buffer, b'gamedata\\los.TDF\0')

    def _ray_call(self, mu, address, size, data):
        sp = mu.reg_read(UC_X86_REG_ESP)
        # 0x433380 calls with edi = the table object (16 bytes: ?, begin, end, capacity) and ecx = the ray object.
        table_object, ray = mu.reg_read(UC_X86_REG_EDI), mu.reg_read(UC_X86_REG_ECX)
        tables_begin = self.native.read(RAYS + 4)
        begin, end = self.native.read(table_object + 4), self.native.read(table_object + 8)
        index = signed((ray - begin) & 0xffffffff) >> 4
        call = [self.native.read(sp + 4), signed(self.native.read(sp + 8)) & 0xffff,
                signed(self.native.read(sp + 12)) & 0xffff, (table_object - tables_begin) // 16, index, (end - begin) // 16]
        self.ray_calls.append(call)
        if self.first_out_of_range is None and not 0 <= index < call[5]:
            self.first_out_of_range = call

    def _fatal(self, mu, address, size, data):
        message = self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        self.fatal = bytes(mu.mem_read(message, 0x200)).split(b'\0')[0].decode('latin-1')
        mu.emu_stop()

    def _call(self, address, args, this, limit):
        # MovementReference.call with a per-case instruction limit (a numlines=8192 table needs tens of millions).
        native, mu = self.native, self.native.mu
        sp = STACK_TOP - (len(args) + 1) * 4
        native.write(sp, STOP)
        for i, value in enumerate(args):
            native.write(sp + 4 + i * 4, value)
        mu.reg_write(UC_X86_REG_ESP, sp)
        mu.reg_write(UC_X86_REG_ECX, this)
        mu.emu_start(address, STOP, timeout=0, count=limit)
        if mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError('Native interpreter failed to return within execution limit')
        return mu.reg_read(UC_X86_REG_EAX)

    def _line_value(self, mu, address, size, data):
        if self.ray_calls[-1][2] != 0:
            return
        sp = mu.reg_read(UC_X86_REG_ESP)
        found = mu.reg_read(UC_X86_REG_EAX) != 0
        value = bytes(mu.mem_read(sp + 0x34, 0x200)).split(b'\0')[0].decode('latin-1') if found else None
        self.line_values.append(value)

    def load(self, text, limit=2000000):
        native, mu = self.native, self.native.mu
        mu.mem_write(TEXT, text + b'\0')
        trampoline = bytearray(b'\x8b\x44\x24\x04\x50\x6a\x00\x68' + struct.pack('<I', len(text)) +
                               b'\x68' + struct.pack('<I', TEXT))
        call_at = 0x4c2f60 + len(trampoline)
        trampoline += b'\xe8' + struct.pack('<i', 0x4c3120 - (call_at + 5))
        trampoline += b'\xb8\x01\x00\x00\x00\xc2\x04\x00'
        mu.mem_write(0x4c2f60, bytes(trampoline))
        mu.mem_write(RAYS, bytes(16))
        try:
            self._call(0x433130, [], RAYS, limit)
            error = None
        except (UcError, RuntimeError, MemoryError) as caught:
            error = f'{type(caught).__name__}: {caught}'
        if error is None and not self.trapped and self.fatal is None and self.first_out_of_range is None:
            return self.dump()
        if error is None:
            error = 'import trap' if self.trapped else 'fatal handler' if self.fatal is not None else 'completed after out-of-range ray'
        return dict(fault=dict(error=error, eip=hex(mu.reg_read(UC_X86_REG_EIP)), imports=self.trapped, fatal=self.fatal,
                               first_out_of_range_ray=self._line_label(self.first_out_of_range),
                               last_line_call=self._line_label(self.ray_calls[-1] if self.ray_calls else None)))

    def _line_label(self, call):
        if not call:
            return None
        return dict(table=call[3], line=call[1], rotation=call[2], ray_index=call[4], ray_count=call[5])

    def vector(self, address, element):
        begin, end = self.native.read(address + 4), self.native.read(address + 8)
        if not begin:
            return []
        return [begin + i * element for i in range((end - begin) // element)]

    def dump(self):
        native = self.native
        tables = []
        for table in self.vector(RAYS, 16):
            rays = []
            for ray in self.vector(table, 16):
                rays.append([list(struct.unpack('<hh', native.mu.mem_read(entry, 4))) for entry in self.vector(ray, 4)])
            tables.append(rays)
        begin = native.read(RAYS + 4)
        accessor = []
        for k in list(range(0, len(tables) + 2)) + [0xffff, 0x10000, 0x10001, 0x10002, 0xffffffff]:
            pointer = native.call(0x433500, [k], this=RAYS)
            accessor.append(dict(k=k, table_index=(signed((pointer - begin) & 0xffffffff) // 16) if begin else None))
        return dict(tables=tables, accessor=accessor, ray_calls=len(self.ray_calls), line_values=self.line_values, benign_imports=self.benign)


def synthetic_cases(original):
    base = original.decode('latin-1')
    spaced = base.replace('line1= 1, 0, 1;', 'line1=   1 ,  0 ,,  1   ;')
    assert spaced != base, 'extra-spaces case no longer modifies los.tdf'
    yield 'extra-spaces', spaced
    yield 'negative-and-plus', ('[TABLEINFO]{numtables=2;}\n[TABLE1]{numlines=2;\nline1=3,-1,2,+4,-5,0,-0;\n'
                                'line2= 2, -32768, 32767, 32768, -32769;}\n[TABLE2]{numlines=1; line1=1,7,-7;}\n')
    yield 'tabs-and-junk', ('[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=3;\nline1=2,\t1,\t2 ,3x,4;\n'
                            'line2=2, 1\t2, 3, 4, 5;\nline3=  ;}\n')
    yield 'extra-tokens', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=1; line1=1, 5, 6, 7, 8, 9;}\n'
    yield 'zero-count', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=2; line1=0, 5, 6; line2=1, 2, 3;}\n'
    # the pair count is movsx'd from 16 bits: 65536 -> 0, 65537 -> 1.
    yield 'count-int16-wrap', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=2; line1=65536, 5, 6; line2=65537, 2, 3, 4;}\n'
    # a negative pair count resizes the ray vector to (unsigned) 2^32-2 entries: expected native fault.
    yield 'negative-count', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=2; line1=1, 5, 6; line2=-2, 1, 1;}\n'
    yield 'numlines-zero-and-negative', ('[TABLEINFO]{numtables=3;}\n[TABLE1]{numlines=0; line1=1,1,1;}\n'
                                         '[TABLE2]{numlines=-1; line1=1,1,1;}\n[TABLE3]{numlines=1; line1=1,2,2;}\n')
    yield 'numlines-zero', ('[TABLEINFO]{numtables=2;}\n[TABLE1]{numlines=0; line1=1,1,1;}\n'
                            '[TABLE2]{numlines=1; line1=1,2,2;}\n')
    yield 'numtables-zero','[TABLEINFO]{numtables=0;}\n[TABLE1]{numlines=1; line1=1,1,1;}\n'
    yield 'numtables-negative', '[TABLEINFO]{numtables=-1;}\n[TABLE1]{numlines=1; line1=1,1,1;}\n'
    # 0x4c48c0 copies at most 0x1ff characters: the second number is cut to "3".
    yield 'long-line-truncation', ('[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=2;\nline1=1,' + ' ' * 505 + '12,345;\n'
                                   'line2=  \t 1 , 7 , 8 \t ;}\n')
    yield 'missing-line-and-table', ('[TABLEINFO]{numtables=3;}\n[TABLE1]{numlines=3; line1=1,1,1; line3=1,3,3;}\n'
                                     '[TABLE3]{numlines=1; line1=1,9,9;}\n')
    yield 'numlines-less-than-lines', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=1; line1=1,1,2; line2=1,3,4;}\n'
    yield 'case-and-comments', ('// c\n[tableinfo]{NumTables=1; /* block */}\n[table1]{NUMLINES=1; // x\n'
                                'LINE1= 2, 1, 0, 2, 0;}\n')
    yield 'overflow-digits', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=1; line1=2, 4294967297, 65537, 99999999999, -65535;}\n'
    yield 'odd-pair-count', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=1; line1=2, 1, 2, 3;}\n'
    yield 'count-exceeds-tokens', '[TABLEINFO]{numtables=1;}\n[TABLE1]{numlines=1; line1=3, 1, 2;}\n'
    yield 'no-tableinfo', '[TABLE1]{numlines=1; line1=1,1,1;}\n'
    # --- TDF parser (0x4c33a0 / 0x4c3e40) and lookup details ---
    h = '[TABLEINFO]{numtables=1;}\n'
    # repeated key: the later assignment overwrites (also across case variants); repeated section: first wins.
    yield 'duplicate-keys', h + '[TABLE1]{numlines=2; numlines=3; line1=1,1,1; LINE1=1,2,2; line2=1,4,4; line2=1,5,5; Line3=1,6,6; line3=1,7,7;}\n'
    yield 'duplicate-sections', ('[TABLEINFO]{numtables=2;}[tableinfo]{numtables=1;}\n[TABLE1]{numlines=1; line1=1,1,1;}\n'
                                 '[TABLE1]{numlines=1; line1=1,2,2;}[TABLE2]{}[TABLE2]{numlines=1; line1=1,3,3;}\n')
    # comments become same-length spaces ("//" blanks '\r' but keeps '\n'; "/*" blanks newlines), which is visible
    # in the strtok input and in the 0x1ff truncation; "/*/" does not close.
    yield 'comments-in-values', (h + '[TABLE1]{numlines=4; line1=2,1,1, // x\r\n 2,2; line2=2,1/*a\r\nb*/,1,2,2;\n'
                                 'line3=1,' + ' ' * 490 + '/*' + 'c' * 12 + '*/9,9; line4=1,/*/ 3,3 */4,4;}\n')
    yield 'unterminated-block-comment', h + '[TABLE1]{numlines=1; line1=1,1,1;} /* rest x'
    # only ' ', \t, \r, \n are trimmed from names and values; \v, \f and 0xa0 stay (atoi still skips \v/\f).
    yield 'tdf-whitespace-set', (h + '[TABLE1]{numlines=4; line1=\x0b1,\x0c2,3\x0b; line2=\xa0 1,3,3 \xa0;\n'
                                 '\x0bline3=1,5,5; line4\t\r\n=\r\n1,6,6\t;}\n[\x0bTABLE2]{}\n')
    yield 'section-name-spaces', '[ TABLEINFO\t]\r\n\t{numtables=1;}\n[\r\nTABLE1 ]\n\n{numlines=1; line1=1,1,1;}\n'
    # a field key runs to the next '=' anywhere: "foo [BAR]{a" swallows the sub-section and the '}' closes TABLE1.
    yield 'key-swallows-section', h + '[TABLE1]{numlines=2; foo [BAR]{a=1;} line1=1,1,1; line2=1,2,2;}\n'
    yield 'field-without-equals', h + '[TABLE1]{numlines; line1=1,1,1; numlines=1;}\n'
    # a '}' at the root ends parsing silently; nested sections are not searched by the TABLE lookup.
    yield 'stray-close-at-root', h + '}[TABLE1]{numlines=1; line1=1,1,1;}\n'
    yield 'nested-sections', '[TABLEINFO]{numtables=2; [TABLE2]{numlines=1; line1=1,6,6;}}\n[TABLE1]{numlines=2; [X]{line1=1,4,4;} line2=1,5,5;}\n'
    # only A-Z fold in _stricmp: 0xc0 does not match 0xe0.
    yield 'high-byte-case', h + '[TABLE1]{numlines=2; line1=1,1,1; LINE1\xc0=1,2,2; line2\xe0=1,3,3; line2=1,8,8; LINE2\xc0=1,9,9;}\n'
    # malformed text: fatal handler 0x4b6290
    yield 'fatal-missing-semicolon', h + '[TABLE1]{numlines=1; line1=1,7,7}\n'
    yield 'fatal-unclosed-section', h + '[TABLE1]{numlines=1; line1=1,1,1;\n'
    yield 'fatal-no-equals', h + '[TABLE1]{numlines=1; line1=1,1,1;} / * \n'
    yield 'fatal-no-bracket', h + '[TABLE1{numlines=1; line1=1,1,1;}\n'
    yield 'fatal-no-brace', h + '[TABLE1] numlines=1; {line1=1,1,1;}\n'
    # --- int16 ray index in 0x433380 ---
    yield 'numlines-8192', h + '[TABLE1]{numlines=8192; line8192=1,2,3; line1=1,4,5;}\n'
    yield 'numlines-8193', h + '[TABLE1]{numlines=8193; line1=1,1,1;}\n'
    yield 'numlines-32767', h + '[TABLE1]{numlines=32767;}\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=Path('local/original/TotalA.exe'))
    parser.add_argument('--cob', type=Path, default=Path('local/viewer-assets/armcom.cob'))
    parser.add_argument('--tdf', type=Path, default=Path('local/visibility/los.tdf'))
    parser.add_argument('--output', type=Path, default=Path('local/visibility/native-los-tables.json'))
    args = parser.parse_args()
    executable, cob, original = args.exe.read_bytes(), args.cob.read_bytes(), args.tdf.read_bytes()
    cases = [('los.tdf', original.decode('latin-1'))] + list(synthetic_cases(original))
    results = []
    for name, text in cases:
        loader = LosLoader(executable, cob)
        result = loader.load(text.encode('latin-1'), limit=80000000 if name in ('numlines-8192', 'numlines-8193', 'numlines-32767') else 2000000)
        results.append(dict(name=name, text=text, **result))
        if 'fault' in result:
            print(f'NATIVE_LOS_TABLES {name}: fault {result["fault"]}')
        else:
            print(f'NATIVE_LOS_TABLES {name}: {len(result["tables"])} tables, rays '
                  f'{[len(t) for t in result["tables"]]}, {result["ray_calls"]} line calls')
    if 'fault' in results[0]:
        raise SystemExit('original los.tdf failed to load natively')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(exe_sha256=EXE_HASH, tdf_sha256=hashlib.sha256(original).hexdigest(),
                                           cases=results)), encoding='utf-8')
    print(f'NATIVE_LOS_TABLES wrote {len(results)} cases to {args.output}')


if __name__ == '__main__':
    main()
