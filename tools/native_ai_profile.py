"""Oracle O1: run the ORIGINAL AI profile interpreter of TotalA.exe in Unicorn and dump the per-type AI arrays.

Original code that executes unmodified:
  * registration 0x406f00 (plan 0x406c90 / weight 0x406db0 / limit 0x406e40, flags 8) through 0x4b7620, and the
    three console tables 0x501d38/0x501f48/0x501fd0 through 0x4b7760 plus the fallback 0x4b78e0(0x417890, 4),
    exactly as 0x4195c4..0x4195e4 does (so dispatch sees the real command table);
  * per-type defaults 0x409470 for every player context;
  * category map fill 0x488e70 (sscanf " %s %n" + implicit ALL, map 0x488c50 / 0x488fb0) per unit definition;
  * profile load 0x4648e0 (or ReloadAIProfiles body 0x40a100): script runner 0x4b7a30, tokenizer 0x4b7440, %n
    substitution 0x4b74f0, dispatch 0x4b7900 (_strlwr copy 0x4c9290, _stricmp 0x4f8a70 lower_bound), argument
    getters 0x4b73c0/0x4b73e0/0x4b7410 with CRT atoi 0x4e4f70 / atof 0x4e4560, name resolution 0x488d30, weight
    0x409dc0 (CRT _ftol 0x4e43a0), limit 0x409e90, FBI passes 0x409f80 / 0x40a040;
  * the unknown-command fallback 0x417890 including its wildcard matcher 0x4bc370 and sprintf 0x4e42b0;
  * the limit test 0x409f20;
  * separately, CRT atof 0x4e4560 (_fltin2 0x4eaf00, __strgtold12 0x4f3d10, __mtold12 0x4f8c40, __multtenpow12
    0x4f9390, __ld12mul 0x4f90d0, _ld12tod 0x4f3990/0x4f37c0) followed by x87 `fstp dword` over a deterministic
    string corpus (the weight path narrows atof's double to float32 that way), and an assertion that the 12-byte
    power-of-ten tables 0x5116f0 / 0x511850 equal their mathematical derivation and the constants in
    godot/ai_profile.gd.

Stubs (host services, each documented; nothing inside the interpreter is replaced):
  * Heap: 0x4d8660 / 0x4d83c0 / 0x4e8890 -> bump allocator; frees 0x4d8670 / 0x4d85b0 / 0x4e8820 -> ret.
  * _getptd 0x4eb0f0 -> one zeroed per-thread block. Win32 imports trap (Enter/LeaveCriticalSection are no-ops).
  * 0x4356c0(7) (settings slot-7 string, thiscall ret 4) -> returns the case's profile path (e.g. "ai\\default.txt").
  * 0x4bbe50(name, &len) (game file loader, stdcall ret 8) -> case file table; unknown name -> 0 (load failure).
    Every requested name is recorded.
  * Fallback side effects: 0x485f50 (unit spawn, stdcall ret 0x20) records (arg0 = atoi(argv[1]), arg1 = type id);
    0x47ddc0 (spawn position helper, ret 8) -> ret; 0x4bb5b0 (debugdat script open, ret 4) records the path and
    returns 0 (no debugdat directory exists in the GOG install).
  * Every other registered console command handler entry is replaced by `ret 4` that records name and argv
    (their game effects are outside the profile interpreter).
Native faults: only a Unicorn UcError counts as a native crash. Harness failures (import trap, execution limit,
bump-heap exhaustion) abort the run. A crash is classified from evidence: eip inside the tokenizer 0x4b7440..0x4b74ef
-> token_storage_overflow; otherwise, when the last recorded event is the debugdat open with a path of more than 59
characters (sprintf wrote past the 60-byte buffer at [esp+0x28] of 0x417890, whose return address follows it) ->
fallback_path_overflow; anything else -> unclassified (never matches the port).
Synthetic game state (not code): game object at [0x511de8]; difficulty game+0x37eee; type count game+0x1438f and
the 0x249-byte definition array [game+0x1439b] with +0x20 unitname, +0xbe ai_weight, +0xfe ai_limit, +0x21e id,
+0x241 bit 5 downloadable, sorted from index 1 by _stricmp as the FBI loader does (adjacency is re-checked with
the native _stricmp); player records game+0x1b63+i*0x14b (+0 present word, +0x73 type byte, +0x74 AI object
pointer, only tested for non-zero); AI contexts [0x5119c0+i*4] with the six per-type vectors (+0x81 short,
+0xa1/+0xb1 byte, +0xc1/+0xd1/+0xe1 int) sized to the type count, as 0x409470 expects.

Writes local/ai/native-ai-profile.json (full cases) and analysis/native-ai-profile-validation.json (summary).
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct

from native_movement_reference import MovementReference
from native_cob_reference import EXE_HASH, UC_HOOK_CODE, STOP, STACK_TOP
from unicorn import UcError
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ECX

GAME_POINTER = 0x511de8
HEAP = 0x2000000
HEAP_SIZE = 0x1000000
DATA = 0x3000000
PTD = 0x3100000
TRAP = 0x3200000
BENIGN_IMPORTS = {'KERNEL32.dll!EnterCriticalSection': 4, 'KERNEL32.dll!LeaveCriticalSection': 4}
CONSOLE_TABLES = (0x501d38, 0x501f48, 0x501fd0)
PROFILE_HANDLERS = {0x406c90, 0x406db0, 0x406e40}
PLAN_FLAG = 0x501774
STRIDE = 0x249
PLAYER = 0x1b63
PLAYER_STRIDE = 0x14b

# players: [present word != 0, type byte, AI object pointer != 0]
TOKENIZER = (0x4b7440, 0x4b74f0)
FALLBACK_BUFFER = 60
ATOF_STUB = DATA + 0x1000
ATOF_DOUBLE = DATA + 0x100
ATOF_FLOAT = DATA + 0x108
POW10_TABLES = {'positive': 0x5116f0, 'negative': 0x511850}

SKIRMISH = [[1, 1, 1], [1, 2, 1]] + [[0, 0, 0]] * 8
MIXED = [[1, 1, 1], [1, 2, 1], [1, 2, 1], [1, 3, 0], [0, 2, 1], [1, 2, 0], [1, 1, 0], [0, 0, 0], [1, 0, 1], [1, 2, 1]]
ALL_AI = [[1, 2, 1]] * 10
NO_AI = [[1, 1, 1], [1, 3, 0]] + [[0, 0, 0]] * 8

SYNTHETIC_UNITS = [
    dict(unitname='ARMCOM', category='ARM COMMANDER LEVEL1 WEAPON'),
    dict(unitname='ARMSOLAR', category='ARM ENERGY LEVEL1 NOWEAPON'),
    dict(unitname='armmex', category='ARM METAL level1'),
    dict(unitname='ARMFLASH', category='ARM TANK LEVEL1 WEAPON'),
    dict(unitname='ARM_X', category='ARM'),
    dict(unitname='ARMZ', category=''),
    dict(unitname='CORAK', category='CORE KBOT LEVEL1 WEAPON'),
    dict(unitname='CORFLAK', category='CORE LEVEL3 strategic weapon', downloadable=1, ai_weight='weight CORFLAK 6', ai_limit='limit CORFLAK 8'),
    dict(unitname='ARMMARK', category='ARM KBOT NOWEAPON LEVEL2', downloadable=1, ai_limit='limit ARMMARK 2'),
    dict(unitname='ARMSNIPE', category='ARM KBOT LEVEL2 WEAPON', downloadable=1, ai_weight='weight ARMAMPH 0.5', ai_limit='limit ARMAMPH 20'),
    dict(unitname='ARMAMPH', category='ARM KBOT LEVEL2 WEAPON', downloadable=1, ai_weight='weight ARMAMPH 0.5', ai_limit='limit ARMAMPH 20'),
    dict(unitname='CORDL', category='CORE LEVEL2 WEAPON', downloadable=1, ai_weight='weight LEVEL2 0.5'),
    dict(unitname='CORLIM', category='CORE LEVEL2', downloadable=1, ai_weight='limit CORLIM 3'),
    dict(unitname='CORMULTI', category='CORE  LEVEL2\tSPECIAL', downloadable=1, ai_weight='weight CORE 0.9 # x'),
    dict(unitname='DOWNNOAI', category='CORE', downloadable=1),
    dict(unitname='NOTDOWN', category='CORE SPECIAL', downloadable=0, ai_weight='weight NOTDOWN 0.1', ai_limit='limit NOTDOWN 1'),
    dict(unitname='A', category='A B'),
    dict(unitname='B2', category='a b'),
    dict(unitname='CORE', category='ARM'),
]
# FBI ai_weight strings that switch the plan flag: an earlier id turns it off, a later id tries to apply a weight
# (0x409f80 / 0x40a040 set the flag once before their loop, not per type).
SYNTHETIC_PLAN_UNITS = [dict(unit, ai_weight={'ARMAMPH': 'plan hard', 'CORDL': 'weight LEVEL2 0.5', 'CORLIM': 'plan any',
                                              'CORMULTI': 'weight CORE 0.9'}.get(unit['unitname'], unit.get('ai_weight', '')))
                        for unit in SYNTHETIC_UNITS]
UNIT_SETS = {'synthetic': SYNTHETIC_UNITS, 'synthetic_plan': SYNTHETIC_PLAN_UNITS}


def stricmp_key(name):
    data = name if isinstance(name, bytes) else name.encode('latin-1')
    return bytes(c + 32 if 65 <= c <= 90 else c for c in data)


class ProfileOracle:
    def __init__(self, executable, cob, units, players, difficulty, files, profile_name):
        self.native = native = MovementReference(executable, cob)
        mu = self.mu = native.mu
        mu.mem_map(HEAP, HEAP_SIZE)
        mu.mem_map(DATA, 0x100000)
        mu.mem_map(PTD, 0x1000)
        mu.mem_map(TRAP, 0x10000)
        self.executable = executable
        self.cursor = HEAP
        self.trap_names, self.trapped, self.benign = {}, [], {}
        self.events = []
        self.files = files
        self._redirect_imports()
        mu.hook_add(UC_HOOK_CODE, self._trap, begin=TRAP, end=TRAP + 0xffff)
        for address, argument in [(0x4d8660, 4), (0x4d83c0, 4), (0x4e8890, 4)]:
            mu.mem_write(address, b'\xc3')
            mu.hook_add(UC_HOOK_CODE, self._alloc, begin=address, end=address, user_data=argument)
        for address in (0x4d8670, 0x4d85b0, 0x4e8820):
            mu.mem_write(address, b'\xc3')
        mu.mem_write(0x4eb0f0, b'\xb8' + struct.pack('<I', PTD) + b'\xc3')
        # host services
        self.name_pointer = self.alloc_string(profile_name.encode('latin-1'))
        mu.mem_write(0x4356c0, b'\xb8' + struct.pack('<I', self.name_pointer) + b'\xc2\x04\x00')
        mu.mem_write(0x4bbe50, b'\xc2\x08\x00')
        mu.hook_add(UC_HOOK_CODE, self._load_file, begin=0x4bbe50, end=0x4bbe50)
        mu.mem_write(0x485f50, b'\xc2\x20\x00')
        mu.hook_add(UC_HOOK_CODE, self._spawn, begin=0x485f50, end=0x485f50)
        mu.mem_write(0x47ddc0, b'\xc2\x08\x00')
        mu.mem_write(0x4bb5b0, b'\x31\xc0\xc2\x04\x00')
        mu.hook_add(UC_HOOK_CODE, self._open, begin=0x4bb5b0, end=0x4bb5b0)
        self.handlers = {}
        for table in CONSOLE_TABLES:
            address = table
            while native.read(address):
                handler = native.read(address + 4)
                self.handlers[handler] = self.c_string(native.read(address))
                address += 12
        for handler in self.handlers:
            mu.mem_write(handler, b'\xc2\x04\x00')
            mu.hook_add(UC_HOOK_CODE, self._console, begin=handler, end=handler)
        # game state
        native.write(GAME_POINTER, native.read(GAME_POINTER))  # MovementReference maps GAME and stores it here
        self.game = native.read(GAME_POINTER)
        self.write_game(difficulty, units, players)
        # original registration sequence
        self.call(0x406f00, [])
        for table in CONSOLE_TABLES:
            self.call(0x4b7760, [table])
        self.call(0x4b78e0, [0x417890, 4])
        for index in range(1, self.count):
            self.call(0x488e70, [self.category_pointers[index]], this=self.unit(index))
        for slot in range(10):
            self.call(0x409470, [], this=self.contexts[slot])

    # ---- memory helpers
    def _redirect_imports(self):
        data, native, mu = self.executable, self.native, self.mu
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        base = struct.unpack_from('<I', data, pe + 52)[0]
        descriptor = base + struct.unpack_from('<I', data, pe + 24 + 104)[0]
        index = 0
        while native.read(descriptor + 16):
            dll = bytes(mu.mem_read(base + native.read(descriptor + 12), 64)).split(b'\0')[0].decode()
            slot = base + native.read(descriptor + 16)
            while native.read(slot):
                value = native.read(slot)
                name = f'#{value & 0xffff}' if value & 0x80000000 else bytes(mu.mem_read(base + value + 2, 64)).split(b'\0')[0].decode()
                stub = TRAP + index * 4
                mu.mem_write(stub, b'\xcc')
                self.trap_names[stub] = f'{dll}!{name}'
                native.write(slot, stub)
                slot += 4
                index += 1
            descriptor += 20

    def _trap(self, mu, address, size, data):
        name = self.trap_names.get(address, hex(address))
        sp = mu.reg_read(UC_X86_REG_ESP)
        if name in BENIGN_IMPORTS:
            self.benign[name] = self.benign.get(name, 0) + 1
            mu.reg_write(UC_X86_REG_ESP, sp + 4 + BENIGN_IMPORTS[name])
            mu.reg_write(UC_X86_REG_EIP, self.native.read(sp))
            return
        self.trapped.append(dict(name=name, return_address=hex(self.native.read(sp))))
        mu.emu_stop()

    def alloc(self, count):
        pointer = self.cursor
        self.cursor = (self.cursor + max(count, 1) + 15) & ~7
        if self.cursor >= HEAP + HEAP_SIZE:
            raise MemoryError('bump heap exhausted')
        return pointer

    def alloc_string(self, data):
        pointer = self.alloc(len(data) + 1)
        self.mu.mem_write(pointer, data + b'\0')
        return pointer

    def _alloc(self, mu, address, size, argument):
        mu.reg_write(UC_X86_REG_EAX, self.alloc(self.native.read(mu.reg_read(UC_X86_REG_ESP) + argument)))

    def c_string(self, address, limit=0x200):
        return bytes(self.mu.mem_read(address, limit)).split(b'\0')[0].decode('latin-1')

    def call(self, address, args, this=0, limit=400000000):
        native, mu = self.native, self.mu
        sp = STACK_TOP - (len(args) + 1) * 4
        native.write(sp, STOP)
        for i, value in enumerate(args):
            native.write(sp + 4 + i * 4, value)
        mu.reg_write(UC_X86_REG_ESP, sp)
        mu.reg_write(UC_X86_REG_ECX, this)
        mu.emu_start(address, STOP, timeout=0, count=limit)
        if self.trapped:
            raise RuntimeError(f'import trap {self.trapped}')
        if mu.reg_read(UC_X86_REG_EIP) != STOP:
            raise RuntimeError('did not return within the execution limit')
        return mu.reg_read(UC_X86_REG_EAX)

    # ---- game state
    def unit(self, index):
        return self.units_base + index * STRIDE

    def write_game(self, difficulty, units, players):
        native, mu, game = self.native, self.mu, self.game
        ordered = sorted(units, key=lambda unit: stricmp_key(unit['unitname']))
        self.count = len(ordered) + 1
        self.units_base = self.alloc(self.count * STRIDE)
        mu.mem_write(self.units_base, bytes(self.count * STRIDE))
        self.category_pointers = [0]
        for index, unit in enumerate(ordered, start=1):
            base = self.unit(index)
            mu.mem_write(base + 0x20, unit['unitname'].encode('latin-1')[:0x1f])
            mu.mem_write(base + 0xbe, unit.get('ai_weight', '').encode('latin-1')[:0x3f])
            mu.mem_write(base + 0xfe, unit.get('ai_limit', '').encode('latin-1')[:0x3f])
            mu.mem_write(base + 0x21e, struct.pack('<H', index))
            native.write(base + 0x241, (unit.get('downloadable', 0) & 1) << 5)
            self.category_pointers.append(self.alloc_string(unit.get('category', '').encode('latin-1')[:0x63]))
        self.ordered = ordered
        native.write(game + 0x37eee, difficulty)
        native.write(game + 0x1438f, self.count)
        native.write(game + 0x1439b, self.units_base)
        for slot, (present, kind, brain) in enumerate(players):
            record = game + PLAYER + slot * PLAYER_STRIDE
            native.write(record, 0x100 if present else 0)
            mu.mem_write(record + 0x73, bytes([kind]))
            native.write(record + 0x74, DATA + 0x10 if brain else 0)
        self.contexts = []
        for slot in range(10):
            context = self.alloc(0x120)
            mu.mem_write(context, bytes(0x120))
            for field, element in ((0x81, 2), (0xa1, 1), (0xb1, 1), (0xc1, 4), (0xd1, 4), (0xe1, 4)):
                begin = self.alloc(self.count * element)
                native.write(context + field, begin)
                native.write(context + field + 4, begin + self.count * element)
            native.write(0x5119c0 + slot * 4, context)
            self.contexts.append(context)

    def check_order(self):
        for index in range(1, self.count - 1):
            if signed32(self.call(0x4f8a70, [self.unit(index) + 0x20, self.unit(index + 1) + 0x20])) >= 0:
                raise AssertionError(f'unit order not ascending under native _stricmp at {index}')

    # ---- hooks
    def _load_file(self, mu, address, size, data):
        sp = mu.reg_read(UC_X86_REG_ESP)
        name = self.c_string(self.native.read(sp + 4))
        length_pointer = self.native.read(sp + 8)
        content = self.files.get(name.lower())
        self.events.append(['load_file', name, content is not None])
        if content is None:
            mu.reg_write(UC_X86_REG_EAX, 0)
            return
        pointer = self.alloc(len(content) + 1)
        mu.mem_write(pointer, content + b'\0')
        self.native.write(length_pointer, len(content))
        mu.reg_write(UC_X86_REG_EAX, pointer)

    def _argv(self, command):
        return [bytes(self.mu.mem_read(self.native.read(command + i * 4), 0x80)).split(b'\0')[0].decode('latin-1')
                for i in range(min(self.native.read(command + 0xd0), 20))]

    def _spawn(self, mu, address, size, data):
        sp = mu.reg_read(UC_X86_REG_ESP)
        self.events.append(['spawn', signed32(self.native.read(sp + 4)), self.native.read(sp + 8)])

    def _open(self, mu, address, size, data):
        self.events.append(['script_file', self.c_string(self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4))])

    def _console(self, mu, address, size, data):
        command = self.native.read(mu.reg_read(UC_X86_REG_ESP) + 4)
        self.events.append(['console', self.handlers[address], self._argv(command)])

    # ---- results
    def dump(self):
        native, mu = self.native, self.mu
        slots = []
        for context in self.contexts:
            count = self.count
            weights = bytes(mu.mem_read(native.read(context + 0xb1), count))
            weight_locks = struct.unpack(f'<{count}i', mu.mem_read(native.read(context + 0xc1), count * 4))
            limits = struct.unpack(f'<{count}i', mu.mem_read(native.read(context + 0xd1), count * 4))
            limit_locks = struct.unpack(f'<{count}i', mu.mem_read(native.read(context + 0xe1), count * 4))
            slots.append(dict(weight=weights.hex(), weight_lock=list(weight_locks), limit=list(limits), limit_lock=list(limit_locks)))
        return dict(plan_flag=native.read(PLAN_FLAG), slots=slots, events=self.events)

    def limit_checks(self):
        results = []
        for slot in (0, 1):
            for type_id in (0, 1, 2, self.count - 1, self.count, 0x10001, 0x10000 + self.count - 1):
                for count in (-1, 0, 1, 2, 7, 8, 20, 100):
                    results.append([slot, type_id, count, self.call(0x409f20, [slot, type_id, count & 0xffffffff])])
        return results


def signed32(value):
    value &= 0xffffffff
    return value - (1 << 32) if value & 0x80000000 else value


def run_case(executable, cob, case, files):
    oracle = ProfileOracle(executable, cob, case['units_data'], case['players'], case['difficulty'], files, case['profile_name'])
    if case.get('check_order'):
        oracle.check_order()
    results = []
    fault = None
    for operation in case['operations']:
        kind = operation[0]
        oracle.events = []
        oracle.trapped = []
        try:
            if kind == 'set_file':
                files[operation[1].lower()] = case_bytes(operation[2])
                results.append(None)
                continue
            if kind == 'difficulty':
                oracle.native.write(oracle.game + 0x37eee, operation[1])
                results.append(None)
                continue
            if kind == 'players':
                for slot, (present, kind_byte, brain) in enumerate(operation[1]):
                    record = oracle.game + PLAYER + slot * PLAYER_STRIDE
                    oracle.native.write(record, 0x100 if present else 0)
                    oracle.mu.mem_write(record + 0x73, bytes([kind_byte]))
                    oracle.native.write(record + 0x74, DATA + 0x10 if brain else 0)
                results.append(None)
                continue
            oracle.call({'load': 0x4648e0, 'reload': 0x40a100}[kind], [], limit=600000000)
        except UcError as caught:
            eip = oracle.mu.reg_read(UC_X86_REG_EIP)
            fault = dict(operation=len(results), error=f'{type(caught).__name__}: {caught}', eip=hex(eip),
                         kind=classify_fault(eip, oracle.events), events=oracle.events)
            break
        except (RuntimeError, MemoryError) as caught:
            raise RuntimeError(f"harness failure in case {case.get('name')}: {caught}") from caught
        results.append(oracle.dump())
    output = dict(results=results)
    if fault:
        output['fault'] = fault
    else:
        output['limit_checks'] = oracle.limit_checks()
    output['type_names'] = [''] + [unit['unitname'] for unit in oracle.ordered]
    return output


def classify_fault(eip, events):
    if TOKENIZER[0] <= eip < TOKENIZER[1]:
        return 'token_storage_overflow'
    if events and events[-1][0] == 'script_file' and len(events[-1][1]) + 1 > FALLBACK_BUFFER:
        return 'fallback_path_overflow'
    return 'unclassified'


def case_bytes(value):
    return bytes.fromhex(value['hex']) if 'hex' in value else Path(value['path']).read_bytes()


def text_file(text):
    return dict(hex=(text if isinstance(text, bytes) else text.encode('latin-1')).hex())


def synthetic_scripts():
    """(name, script text, difficulties)."""
    all3 = (0, 1, 2)
    yield 'empty', '', (0,)
    yield 'newline-only', '\n\n\n', (0,)
    yield 'no-trailing-newline', 'weight ARM 0.5', (0,)
    yield 'crlf', 'weight ARM 0.5\r\nlimit CORE 3\r\n', (0,)
    yield 'cr-only-joins-lines', 'weight ARM 0.5\rweight CORE 0.25\r', (0,)
    yield 'tabs-vtab-ff', '\tweight\tARM\x0b0.5\x0c\nlimit\x0bCORE 4', (0,)
    yield 'case-commands', 'WEIGHT arm 0.5\nWeIgHt Core 0.3\nLIMIT core 2\nLimit ARMCOM 7\nPLAN EASY\nweight ALL 0.9', all3
    yield 'hash-comments', '# weight ARM 0\nweight ARM 0.5 # trailing\nweight#CORE 0.1\nweight CORE#x 0.1\nweight CORAK #0.7\n  #limit CORE 1\n', (0,)
    yield 'hash-mid-value', 'weight ARM 0.5#9\nlimit CORE 3#\n', (0,)
    yield 'slash-comments', '// weight ARM 0\n//weight CORE 0.1\n/ / x\nweight ARM 0.5 // trailing tokens ignored\n//ARM\n', (0,)
    yield 'nul-in-line', 'weight\0junk ARM 0.5\nweight ARM\0CORE 0.25\nwe\0ight CORE 0.1\nlimit CORE 3\0 9\n', (0,)
    yield 'plan-basic', 'weight ALL 0.9\nplan easy\nweight ARM 0.5\nlimit ARM 1\nplan medium\nweight ARM 0.6\nlimit ARM 2\nplan hard\nweight ARM 0.7\nlimit ARM 3\n', all3 + (3, -1)
    yield 'plan-no-args', 'plan\nweight ARM 0.5\nplan any\nweight CORE 0.5\n', (0,)
    yield 'plan-any-quirk', 'plan hard any\nweight ARM 0.5\nplan any hard\nweight CORE 0.5\nplan ANY\nlimit ARM 4\nplan x any\nlimit CORE 5\n', (0, 2)
    yield 'plan-multi', 'plan easy medium\nweight ARM 0.5\nplan hard easy\nweight CORE 0.5\nplan Medium HARD\nlimit ALL 9\nplan easyx\nlimit ARM 1\n', all3
    yield 'plan-extra-args', 'plan medium 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 easy\nweight ARM 0.5\n', (0, 1)
    yield 'plan-ends-off', 'weight ARM 0.5\nplan hard\n', (0,)
    yield 'lock-explicit-first', 'weight ARMCOM 0.5\nweight ARM 0.5\nweight ARMCOM 0.1\nlimit ARMCOM 3\nlimit ARM 9\nlimit ARMCOM 1\n', (0,)
    yield 'lock-category-first', 'weight ARM 0.5\nweight ARMCOM 0.5\nweight ARM 0.5\nlimit ARM 9\nlimit ARMCOM 3\nlimit ARM 1\n', (0,)
    yield 'category-raise-after-lower', 'weight ARM 0.2\nweight ARMSOLAR 2\nweight ARM 3\nweight CORE 0.01\nweight CORAK 150\n', (0,)
    yield 'names-case-and-unknown', 'weight armcom 0.5\nweight ArmSolar 0.4\nweight ARMMEX 0.3\nweight level1 0.9\nweight NOPE 0\nlimit nope 0\nweight strategic 0.5\nweight STRATEGIC 0.5\n', (0,)
    yield 'unit-vs-category-name', 'weight A 0.5\nweight B 0.5\nweight a 0.5\nweight CORE 0.5\nweight ALL 0.8\nlimit all 6\n', (0,)
    yield 'missing-arguments', 'weight ARM\nlimit CORE\nweight\nlimit\nweight ARMCOM\n', (0,)
    yield 'empty-category-name', 'weight "" 0.5\nweight ARMZ 0.5\nlimit ARMZ 2\n', (0,)
    yield 'twenty-tokens', 'weight ARM 0.5 a b c d e f g h i j k l m n o p q r s t u v w x y z\nlimit CORE 3 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21\n', (0,)
    yield 'weight-zero-negative', 'weight ARM 0\nweight ARM 5\nweight CORE -1\nweight ALL -0.0\n', (0,)
    yield 'limit-non-ai-players', 'limit ALL 5\nlimit ARMCOM 1\nweight ALL 0.5\n', (0,)
    yield 'unknown-commands', 'foo bar\nArmcom 3\narm* 2\n?ORAK\n*\nCOR*K 1 2\nnotacommand\n', (0,)
    yield 'wildcards', 'a*\n*a*m*\n**\nARMCOM*\n*?\nA?*B*\nc*r*\n***a\n?\n??\n*_*\narm?\nARM?? 7\n*COM\n*x -3\n', (0,)
    yield 'wildcard-state-cap', '*' * 40 + 'Q\n' + '*?' * 23 + '\n' + '?*' * 20 + 'MULTI\n' + '*' * 46 + '\n', (0,)
    # found by search: results differ between a 99-, 100- and 101-state cap
    yield 'wildcard-state-cap-boundary', '*****X\n*****M\n******OM\n******X\nA******X\n', (0,)
    yield 'console-commands', 'Radar\nNoShake 1\nAI 1 2\nprintweights\nreloadaiprofiles\nKill 3\nweight ARM 0.5\n', (0,)
    yield 'percent-tokens', 'weight %1 0.5\nweight ARM %0\n%weight ARM 0.5\n', (0,)
    for index, value in enumerate(['0.2', '0.25', '2', '1.5', '1e2', '1E-1', '1d1', '1D-1', '.5', '5.', '-0.5', '+0.5',
                                   '0x10', 'inf', 'nan', '1e40', '1e308', '1e309', '3e7', '2.2e7', '4.3e7', '1e9', '1e17',
                                   '9.3e16', '1e19', '2e19', '1.9999999', '0.29', '0.07', '0.0700000001', 'abc', '12abc',
                                   '--1', '+-1', '1.2.3', 'e5', '1e+', '1e-', '1e-400', '0.999999999', '1.0000001',
                                   '123456789012345678901234567890', '0.3333333333333333333333', '0.575', '0.285',
                                   '1,5', '1e2x', '4e-7', '0.0000001', '0.33', '0.67', '0.07000001', '1.01', '0.51']):
        # LEVEL1 types start at 37 (ARMCOM explicitly 18 and locked), the rest at 100
        yield f'weight-value-{index}', f'weight LEVEL1 0.37\nweight ARMCOM 0.5\nweight ALL {value}\n', (0,)
    for index, value in enumerate(['3', '-1', '0', '+7', '-7', '2147483647', '2147483648', '4294967297', '-2147483649',
                                   '99999999999', '12abc', 'abc', '0x10', '1e3', '3.9', '-0', '+', '-']):
        yield f'limit-value-{index}', f'limit ALL {value}\nlimit ARMCOM {value}\n', (0,)
    # tokenizer storage 0x4b7440: 0x7e bytes of token storage (chars + NULs)
    for total in (126, 127, 128):
        filler = 'x' * (total - len('limit ARMCOM 3 ') - 1)
        yield f'token-storage-{total}', f'limit ARMCOM 3 {filler}\nweight ARM 0.5\n', (0,)
    # 0x417890 sprintf("debugdat\\%s.txt") into a local buffer
    for length in range(40, 67):
        yield f'fallback-token-{length}', 'z' * length + '\nweight ARM 0.5\n', (0,)
    # full weight path through CRT atof: long mantissas, exponent-shifted tiny mantissas, 24/25-digit rounding
    for index, value in enumerate(['0.0000000000000000005e19', '0.00000000000000000001e20', '0.5000000000000000001',
                                   '1.9703343510627747', '0.29000000000000000000001', '0.0000000000000000000096e18',
                                   '0.49999999999999999999999999', '0.999999999999999999999995', '0.2899999999999999999999',
                                   '1' + '0' * 30 + 'e-30', '0.' + '9' * 30, '0.3799999999999999999999999999',
                                   '0.28999999999999997779553950749686919152736663818359375', '2.2250738585072011e-308',
                                   '4e-5201', '1e5201', '0.5e00000000000000001', '5e-00000000000000001']):
        yield f'weight-atof-path-{index}', f'weight LEVEL1 0.37\nweight ARMCOM 0.5\nweight ALL {value}\n', (0,)
    yield 'bare-cr-category', 'weight ARM 0.5\rweight KBOT 0.25\rlimit KBOT 3\n', (0,)
    yield 'spawn-owner-default', 'ARMCOM\nCORAK -2\ncorflak\narm?om 4294967297\n', (0,)
    yield 'wildcard-case-folding', 'armcom 1\nArMsOlAr 2\n*mex 3\nc?r*k 4\nB* 5\n', (0,)


def fuzz_scripts(count, seed):
    rng = random.Random(seed)
    names = [u['unitname'] for u in SYNTHETIC_UNITS] + ['ARM', 'CORE', 'LEVEL1', 'LEVEL2', 'ALL', 'all', 'KBOT', 'strategic',
                                                       'NOPE', 'level3', 'SPECIAL', 'b', 'Armcom', 'corflak', '']
    for index in range(count):
        lines = []
        for _ in range(rng.randint(1, 40)):
            roll = rng.random()
            if roll < 0.35:
                value = rng.choice([f'{rng.random() * rng.choice([1, 2, 5, 100]):.{rng.randint(0, 7)}f}', str(rng.randint(-3, 300)),
                                    f'{rng.random():.3g}', f'{rng.uniform(0.9, 1.1):.9f}'])
                line = f"{rng.choice(['weight', 'Weight', 'WEIGHT'])} {rng.choice(names)} {value}"
            elif roll < 0.65:
                line = f"{rng.choice(['limit', 'Limit', 'LIMIT'])} {rng.choice(names)} {rng.randint(-2, 40)}"
            elif roll < 0.8:
                args = rng.sample(['easy', 'medium', 'hard', 'any', 'EASY', 'Hard', 'x'], rng.randint(0, 3))
                line = ' '.join(['plan'] + args)
            elif roll < 0.9:
                line = rng.choice(['// comment', '#comment', '', '   ', '//ARM', 'weight ARM 0.5 # c'])
            else:
                line = f"{rng.choice(['weight', 'limit'])}\t{rng.choice(names)}  {rng.randint(0, 9)}{rng.choice(['', ' extra', '#', ' // x'])}"
            lines.append(line)
        separator = rng.choice(['\n', '\r\n'])
        text = separator.join(lines) + rng.choice(['', separator])
        yield f'fuzz-{index}', text, (rng.randint(0, 2),)


def build_cases(index):
    real_units = [dict(unitname=u['unitname'], category=u['category'], ai_weight=u['ai_weight'], ai_limit=u['ai_limit'],
                       downloadable=leading_int(u['downloadable']) & 1) for u in index['units']]
    cases = []
    seen = {}
    for name, candidates in sorted(index['profiles']['sources'].items()):
        for candidate in candidates:
            if candidate['sha256'] in seen:
                continue
            seen[candidate['sha256']] = f"{candidate['archive']}/{name}"
            path = f"local/ai/archives/{candidate['archive'].replace('.', '_')}/{name}"
            for difficulty in (0, 1, 2):
                cases.append(dict(name=f"real-{candidate['archive']}-{name}-d{difficulty}", group='real', units='real',
                                  players=SKIRMISH, difficulty=difficulty, profile_name=f'ai\\{name[:-4]}.txt',
                                  files={f'ai\\{name[:-4]}.txt': dict(path=path)}, operations=[['load']]))
    default_path = dict(path='local/ai/resolved/default.txt')
    for difficulty in (0, 1, 2):
        cases.append(dict(name=f'real-default-mixed-players-d{difficulty}', group='real', units='real', players=MIXED,
                          difficulty=difficulty, profile_name='ai\\default.txt', files={'ai\\default.txt': default_path},
                          operations=[['load']], check_order=difficulty == 0))
    cases.append(dict(name='real-missing-profile-falls-back', group='real', units='real', players=SKIRMISH, difficulty=2,
                      profile_name='ai\\air.txt', files={'ai\\default.txt': default_path}, operations=[['load']]))
    cases.append(dict(name='real-no-profile-files', group='real', units='real', players=ALL_AI, difficulty=1,
                      profile_name='ai\\air.txt', files={}, operations=[['load']]))
    cases.append(dict(name='real-reload', group='real', units='real', players=MIXED, difficulty=0,
                      profile_name='ai\\default.txt', files={'ai\\default.txt': default_path},
                      operations=[['load'], ['reload'], ['difficulty', 2], ['reload']]))
    for name, text, difficulties in list(synthetic_scripts()) + list(fuzz_scripts(160, 20260914)):
        for difficulty in difficulties:
            cases.append(dict(name=f'{name}-d{difficulty}', group='synthetic', units='synthetic', players=MIXED,
                              difficulty=difficulty, profile_name='ai\\test.txt',
                              files={'ai\\test.txt': text_file(text)}, operations=[['load']]))
    # FBI ai_weight / ai_limit passes 0x409f80 / 0x40a040
    for players_name, players in (('skirmish', SKIRMISH), ('mixed', MIXED), ('all-ai', ALL_AI), ('no-ai', NO_AI)):
        for script_name, text in (('empty', ''), ('locks', 'weight CORFLAK 0.5\nlimit ARMMARK 9\nweight LEVEL2 0.5\n'),
                                  ('limits-only', 'limit CORFLAK 1\nlimit CORLIM 7\n'), ('lower', 'weight ALL 0.2\n')):
            cases.append(dict(name=f'fbi-{players_name}-{script_name}', group='fbi', units='synthetic', players=players,
                              difficulty=1, profile_name='ai\\test.txt', files={'ai\\test.txt': text_file(text)},
                              operations=[['load']]))
    # 0x409f80 / 0x40a040 set the plan flag once per pass; a type's `plan` string switches off later types
    for players_name, players in (('skirmish', SKIRMISH), ('mixed', MIXED), ('all-ai', ALL_AI)):
        for difficulty in (0, 2):
            cases.append(dict(name=f'fbi-plan-strings-{players_name}-d{difficulty}', group='fbi', units='synthetic_plan',
                              players=players, difficulty=difficulty, profile_name='ai\\test.txt',
                              files={'ai\\test.txt': text_file('weight CORDL 0.5\nlimit ARMAMPH 2\n')}, operations=[['load']]))
    # an existing but empty profile does not fall back to ai\default.txt
    cases.append(dict(name='empty-profile-no-default-fallback', group='synthetic', units='synthetic', players=MIXED, difficulty=0,
                      profile_name='ai\\test.txt', files={'ai\\test.txt': text_file(''), 'ai\\default.txt': text_file('weight ALL 0.5\nlimit ALL 2\n')},
                      operations=[['load']]))
    cases.append(dict(name='reload-plan-flag-persists', group='synthetic', units='synthetic', players=NO_AI, difficulty=0,
                      profile_name='ai\\test.txt', files={'ai\\test.txt': text_file('weight ARM 0.5\nlimit ALL 1\nplan hard\nweight CORE 0.5\n')},
                      operations=[['load'], ['reload'], ['players', MIXED], ['reload'], ['reload']]))
    cases.append(dict(name='reload-changed-file', group='synthetic', units='synthetic', players=MIXED, difficulty=1,
                      profile_name='ai\\test.txt', files={'ai\\test.txt': text_file('weight ALL 0.5\nlimit ARMCOM 2\n')},
                      operations=[['load'], ['set_file', 'ai\\test.txt', text_file('weight ARM 0.5\nlimit ALL 4\n')], ['reload']]))
    return cases


def atof_corpus(seed=20260914):
    """Deterministic byte strings for CRT atof: grammar edges, long mantissas (the 25-digit buffer and its rounding),
    float32 / double rounding boundaries, midpoints, subnormals, overflow, exponent clamps and random fuzz."""
    from fractions import Fraction
    rng = random.Random(seed)
    out = []

    def digits(count, alphabet='0123456789'):
        return ''.join(rng.choice(alphabet) for _ in range(count))

    def exact_decimal(value, significant):
        """value (Fraction > 0) as d.ddd...e±x with `significant` digits, truncated."""
        exponent = 0
        while value >= 10:
            value /= 10
            exponent += 1
        while value < 1:
            value *= 10
            exponent -= 1
        text = ''
        for _ in range(significant):
            digit = int(value)
            text += str(digit)
            value = (value - digit) * 10
        return f'{text[0]}.{text[1:]}e{exponent}'

    out += ['', '+', '-', '.', '-.', '+.', '+.5', '-.5', '5.', '5e', '5e+', '5e-', '5E+0', '5d-1', '5D2', '0x1p3',
            ' \t\n\x0b\x0c\r5', '\x805', '5\x805', '..5', '5..', '1e5.5', '1e-0', '-0', '-0.0e5', '00000', '000.000',
            '0.', '.0', '0e', '0e5', 'e5', '1_000', '1,5', '++1', '+-1', '-+1', '1e++1', '1e+-1', '1e--1', '1ee1',
            '1.2.3', '12abc', 'inf', 'nan', 'INF', '1e0000000000000000005', '1e99999999999', '1e5200', '1e5201',
            '1e-5200', '1e-5201', '0.1e5201', '10e5200', '0.000001e-5195', '9' * 400, '0.' + '0' * 300 + '1',
            '1' + '0' * 300, '0.' + '0' * 30 + '1e5230', '1e308', '1.7976931348623157e308', '1.7976931348623158e308',
            '1.7976931348623159e308', '1.797693134862315807e308', '4.9406564584124654e-324', '2.4703282292062327e-324',
            '2.4703282292062328e-324', '2.2250738585072011e-308', '2.2250738585072014e-308', '1e-400', '3.4028235e38',
            '3.4028236e38', '1.4e-45', '7e-46', '1e-39', '18446744073709551615', '18446744073709551616',
            '1208925819614629174706175', '1208925819614629174706176', '999999999999999999999999', '9999999999999999999999999',
            '99999999999999999999999.5', '0.29', '0.07', '0.575', '0.285', '4.35', '1e23', '8.589973e9', '9007199254740993',
            '9007199254740992.5', '0.1', '0.2', '0.3', '123456789012345678901234567890']
    # Rule witnesses found by searching the native chain (each string's native double differs from the variant's):
    # __strgtold12 0x4f4203 bumps digit[23] when a 25th digit exists. Only a zero decimal exponent keeps all 80 bits
    # (__multtenpow12 clears the low word), so these are 24-digit double midpoints plus one fraction digit; the plain
    # 24-digit midpoint (no bump) is included for contrast.
    out += ['713463255249263272132608.1', '713463255249263272132608', '766168942093647151628288.1',
            '858523302561754682228736.1', '174800582619169069989888.1', '777314792639682792390656.1', '960882756533795367682048.1']
    # __ld12mul 0x4f92cf rounds the 16-bit guard word up only when > 0x8000, or == 0x8000 with bit 16 set: exact
    # products d * 10^k with guard exactly 0x8000 and bit 16 clear (native keeps; round-half-up would change the double).
    out += ['1646513063411645e13', '26109724475865461e11', '688336406815087725e9', '11656958156865e16', '15474043232321e16',
            '6579598767701681e12']
    # 0x4f412a caps the exponent digits at 5201 before the leading-zero adjustment is added: 5000 fraction zeros bring
    # a capped 5201 back into double range (1e200), where an uncapped 5300 would give 1e299.
    out += ['0.' + '0' * 5000 + '1e5300', '0.' + '0' * 5000 + '1e5201', '0.' + '0' * 5000 + '1e5199', '0.' + '0' * 5000 + '1e99999']
    # 24/25-digit buffer: digit[23] in 0..9 with a 25th digit and more, with and without a decimal point / exponent
    for _ in range(1200):
        head = str(rng.randint(1, 9)) + digits(22)
        body = head + rng.choice('0123456789') + digits(rng.randint(0, 12), rng.choice(['0123456789', '9', '0', '5']))
        point = rng.randint(0, len(body))
        text = body if rng.random() < 0.3 else body[:point] + '.' + body[point:]
        if rng.random() < 0.4:
            text = '0.' + '0' * rng.randint(0, 30) + body
        if rng.random() < 0.5:
            text += f"{rng.choice('eEdD')}{rng.choice(['', '-', '+'])}{rng.randint(0, 340)}"
        out.append(text)
    # double and float32 midpoints (exact decimal, truncated to 15..30 significant digits, plus neighbours)
    for _ in range(1500):
        if rng.random() < 0.5:
            bits = rng.randint(1, 0x7fefffffffffffff) if rng.random() < 0.3 else rng.randint(0x3c00000000000000, 0x4100000000000000)
            low = Fraction(struct.unpack('<d', struct.pack('<Q', bits))[0])
            high = Fraction(struct.unpack('<d', struct.pack('<Q', bits + 1))[0])
        else:
            bits = rng.randint(1, 0x7f7fffff) if rng.random() < 0.3 else rng.randint(0x3c000000, 0x43000000)
            low = Fraction(struct.unpack('<f', struct.pack('<I', bits))[0])
            high = Fraction(struct.unpack('<f', struct.pack('<I', bits + 1))[0])
        middle = (low + high) / 2
        target = rng.choice([middle, middle, low, middle + (high - low) / 1024, middle - (high - low) / 1024])
        if target <= 0:
            continue
        out.append(exact_decimal(target, rng.randint(15, 30)))
    # subnormal and overflow edges of the double conversion
    for _ in range(600):
        out.append(f"{rng.randint(1, 9)}.{digits(rng.randint(0, 24))}e{rng.choice(['-', ''])}{rng.choice([rng.randint(300, 330), rng.randint(4900, 4960), rng.randint(5190, 5210)])}")
    # the auditor's mixed generator
    for _ in range(3000):
        kind = rng.random()
        if kind < 0.3:
            text = f"{digits(rng.randint(0, 3))}.{digits(rng.randint(1, 20))}"
        elif kind < 0.5:
            text = digits(rng.randint(1, 25))
        elif kind < 0.7:
            text = f"{digits(rng.randint(1, 18))}.{digits(rng.randint(0, 18))}{rng.choice('eEdD')}{rng.choice(['', '-', '+'])}{rng.randint(0, 45)}"
        else:
            text = f"0.{'0' * rng.randint(0, 40)}{digits(rng.randint(1, 30))}e{rng.randint(-10, 60)}"
        out.append(text)
    # grammar fuzz
    for _ in range(1500):
        out.append(digits(rng.randint(1, 30), '0123456789.+-eEdD x\t0000'))
    return [text.encode('latin-1') for text in out]


def native_atof_checks(executable, cob, strings):
    oracle = ProfileOracle(executable, cob, SYNTHETIC_UNITS, SKIRMISH, 0, {}, 'ai\\test.txt')
    mu = oracle.mu
    # push [esp+4]; call atof; add esp, 4; fst qword [ATOF_DOUBLE]; fstp dword [ATOF_FLOAT]; ret
    code = (b'\xff\x74\x24\x04' + b'\xe8' + struct.pack('<i', 0x4e4560 - (ATOF_STUB + 9)) + b'\x83\xc4\x04'
            + b'\xdd\x15' + struct.pack('<I', ATOF_DOUBLE) + b'\xd9\x1d' + struct.pack('<I', ATOF_FLOAT) + b'\xc3')
    mu.mem_write(ATOF_STUB, code)
    rows = []
    start = oracle.cursor
    for text in strings:
        oracle.cursor = start
        oracle.call(ATOF_STUB, [oracle.alloc_string(text)])
        rows.append([text.hex(), bytes(mu.mem_read(ATOF_DOUBLE, 8)).hex(), bytes(mu.mem_read(ATOF_FLOAT, 4)).hex()])
    return rows


def check_pow10_tables(executable, cob):
    """The 12-byte tables used by __multtenpow12 equal the derivation and the port's constants."""
    from fractions import Fraction
    import re
    native = MovementReference(executable, cob)
    port_text = Path('godot/ai_profile.gd').read_text(encoding='utf-8')
    result = {}
    for name, address in POW10_TABLES.items():
        negative = name == 'negative'
        match = re.search(r'const _POW10_%s := \[(.*?)\]' % ('NEG' if negative else 'POS'), port_text, re.S)
        port = re.findall(r'"([0-9a-f]{24})"', match.group(1)) if match else []
        derived = []
        for index in range(29):
            group, last = divmod(index, 7)
            power = (last + 1) * 8 ** group
            value = Fraction(1, 10 ** power) if negative else Fraction(10 ** power)
            exponent = value.numerator.bit_length() - value.denominator.bit_length()
            while Fraction(2) ** exponent > value:
                exponent -= 1
            while Fraction(2) ** (exponent + 1) <= value:
                exponent += 1
            mantissas = []
            for bits in (64, 80):
                scaled = value / Fraction(2) ** (exponent - bits + 1)
                floor = scaled.numerator // scaled.denominator
                mantissas.append(floor + (1 if scaled - floor >= Fraction(1, 2) else 0))
            derived.append(((mantissas[0] << 16 | (mantissas[1] & 0xffff)).to_bytes(10, 'little')
                            + struct.pack('<H', exponent + 0x3fff)).hex())
        table = [bytes(native.mu.mem_read(address + 12 * index, 12)).hex() for index in range(29)]
        if not (table == derived == port):
            raise AssertionError(f'power-of-ten table {name} at {address:#x}: executable, derivation and port differ')
        result[name] = dict(address=hex(address), entries=29, executable_equals_derivation_equals_port=True)
    return result


def leading_int(value):
    """CRT atoi of the TDF value (0x4c46c0 uses atoi); None -> 0."""
    if value is None:
        return 0
    text = value.lstrip(' \t\n\r\x0b\x0c')
    sign, digits = 1, 0
    if text[:1] in '+-':
        sign = -1 if text[0] == '-' else 1
        text = text[1:]
    for char in text:
        if not char.isdigit():
            break
        digits = digits * 10 + int(char)
    return sign * digits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=Path('local/original/TotalA.exe'))
    parser.add_argument('--cob', type=Path, default=Path('local/viewer-assets/armcom.cob'))
    parser.add_argument('--index', type=Path, default=Path('local/ai/index.json'))
    parser.add_argument('--output', type=Path, default=Path('local/ai/native-ai-profile.json'))
    parser.add_argument('--summary', default='analysis/native-ai-profile-validation.json')
    parser.add_argument('--only', default=None, help='substring filter on case names')
    args = parser.parse_args()
    executable, cob = args.exe.read_bytes(), args.cob.read_bytes()
    index = json.loads(args.index.read_text(encoding='utf-8'))
    cases = build_cases(index)
    if args.only:
        cases = [case for case in cases if args.only in case['name']]
    real_units = [dict(unitname=u['unitname'], category=u['category'], ai_weight=u['ai_weight'], ai_limit=u['ai_limit'],
                       downloadable=leading_int(u['downloadable']) & 1) for u in index['units']]
    pow10 = check_pow10_tables(executable, cob)
    corpus = atof_corpus()
    atof_rows = native_atof_checks(executable, cob, corpus)
    print(f'NATIVE_AI_PROFILE atof corpus {len(atof_rows)} strings; power-of-ten tables match')
    faults = []
    for number, case in enumerate(cases):
        case['units_data'] = real_units if case['units'] == 'real' else UNIT_SETS[case['units']]
        files = {name.lower(): case_bytes(value) for name, value in case['files'].items()}
        result = run_case(executable, cob, case, files)
        del case['units_data']
        case.update(result)
        if 'fault' in result:
            faults.append(dict(name=case['name'], kind=result['fault']['kind'], eip=result['fault']['eip']))
            print(f"NATIVE_AI_PROFILE {case['name']}: fault {result['fault']['kind']} at {result['fault']['eip']}")
        elif number % 25 == 0:
            print(f"NATIVE_AI_PROFILE {number + 1}/{len(cases)} {case['name']}")
    file_hashes = {}
    for case in cases:
        for value in list(case['files'].values()):
            if 'path' in value:
                file_hashes[value['path']] = hashlib.sha256(Path(value['path']).read_bytes()).hexdigest()
    payload = dict(exe_sha256=EXE_HASH, index_sha256=hashlib.sha256(args.index.read_bytes()).hexdigest(),
                   synthetic_units=SYNTHETIC_UNITS, unit_sets=UNIT_SETS, file_hashes=file_hashes, atof=atof_rows, cases=cases)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload), encoding='utf-8')
    groups = {}
    for case in cases:
        groups[case['group']] = groups.get(case['group'], 0) + 1
    ai_limit_ids = None
    real_stats = {}
    for case in cases:
        if case['group'] != 'real' or 'fault' in case or not case['name'].endswith(('-d0', '-d1', '-d2')) or 'mixed' in case['name']:
            continue
        names = case['type_names']
        if ai_limit_ids is None:
            ai_limit_ids = [names.index(u['unitname']) for u in index['units'] if u['ai_limit']]
        slot = case['results'][0]['slots'][1]
        count = len(slot['limit'])
        events = {}
        for event in case['results'][0]['events']:
            events[event[0]] = events.get(event[0], 0) + 1
        real_stats[case['name']] = dict(
            slot1_weight_locks=sum(slot['weight_lock']), slot1_limit_locks=sum(slot['limit_lock']),
            slot1_weights_not_100=sum(1 for i in range(1, count) if int(slot['weight'][2 * i:2 * i + 2], 16) != 100),
            slot1_limits_set=sum(1 for i in range(1, count) if slot['limit'][i] != -1),
            fbi_ai_limit_types_left_unlimited=sum(1 for i in ai_limit_ids if slot['limit'][i] == -1),
            events=events)
    summary = dict(
        oracle='tools/native_ai_profile.py', comparator='godot/compare_native_ai_profile.gd', exe_sha256=EXE_HASH,
        cases=len(cases), groups=groups, native_fault_cases=faults,
        real_profile_inputs={path: digest for path, digest in sorted(file_hashes.items())},
        units_real=len(real_units), units_synthetic=len(SYNTHETIC_UNITS), unit_sets=sorted(UNIT_SETS),
        atof_strings=len(atof_rows), atof_distinct_doubles=len({row[1] for row in atof_rows}), pow10_tables=pow10,
        executed_original=['0x406f00', '0x4b7620', '0x4b7760', '0x4b78e0', '0x488e70', '0x488c50', '0x409470', '0x4648e0',
                           '0x40a100', '0x4b7a30', '0x4b7440', '0x4b74f0', '0x4b7900', '0x406c90', '0x406db0', '0x406e40',
                           '0x488d30', '0x409dc0', '0x409e90', '0x409f80', '0x40a040', '0x409f20', '0x417890', '0x4bc370',
                           '0x4e4560 atof chain (0x4eaf00, 0x4f3d10, 0x4f8c40, 0x4f9390, 0x4f90d0, 0x4f3990/0x4f37c0)',
                           '0x4e4f70 atoi', '0x4e42b0 sprintf', '0x4f8a70 _stricmp'],
        stubs=['heap 0x4d8660/0x4d83c0/0x4e8890 and frees', '_getptd 0x4eb0f0', 'slot-7 name 0x4356c0',
               'file loader 0x4bbe50', 'unit spawn 0x485f50 (recorded)', 'spawn position 0x47ddc0',
               'debugdat open 0x4bb5b0 (recorded, returns 0)', 'non-profile console handlers (recorded, ret 4)',
               'Win32 imports trap (Enter/LeaveCriticalSection no-ops); a trap aborts the run'],
        fault_classification='UcError only; eip in 0x4b7440..0x4b74ef -> token_storage_overflow; last event a debugdat '
                             'open with path > 59 chars -> fallback_path_overflow; else unclassified',
        real_profile_results_skirmish_slot1=real_stats,
        fbi_ai_limit_types=len(ai_limit_ids or []))
    if args.summary:
        Path(args.summary).write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(f'NATIVE_AI_PROFILE wrote {len(cases)} cases ({len(faults)} native faults) to {args.output}')


if __name__ == '__main__':
    main()
