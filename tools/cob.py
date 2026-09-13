"""Validated TA COB v4 decoder and annotated disassembly (not a decompiler)."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from ta_assets import FormatError, span, unpack

# Binary opcode identities cross-checked against TotalA.exe at 0x004b0da0.
OPCODES = {
    0x10001000: ('MOVE', 2), 0x10002000: ('TURN', 2),
    0x10003000: ('SPIN', 2), 0x10004000: ('STOP_SPIN', 2),
    0x10005000: ('SHOW', 1), 0x10006000: ('HIDE', 1),
    0x10007000: ('CACHE', 1), 0x10008000: ('DONT_CACHE', 1),
    0x1000B000: ('MOVE_NOW', 2), 0x1000C000: ('TURN_NOW', 2),
    0x1000D000: ('SHADE', 1), 0x1000E000: ('DONT_SHADE', 1),
    0x1000F000: ('EMIT_SFX', 1), 0x10011000: ('WAIT_TURN', 2),
    0x10012000: ('WAIT_MOVE', 2), 0x10013000: ('SLEEP', 0),
    0x10021001: ('PUSH_CONSTANT', 1), 0x10021002: ('PUSH_LOCAL', 1),
    0x10021004: ('PUSH_STATIC', 1), 0x10022000: ('CREATE_LOCAL', 0),
    0x10023002: ('POP_LOCAL', 1), 0x10023004: ('POP_STATIC', 1),
    0x10024000: ('POP_STACK', 0),
    0x10031000: ('ADD', 0), 0x10032000: ('SUB', 0),
    0x10033000: ('MUL', 0), 0x10034000: ('DIV', 0),
    0x10035000: ('BIT_AND', 0), 0x10036000: ('BIT_OR', 0),
    0x10037000: ('BIT_XOR', 0), 0x10038000: ('BIT_NOT', 0),
    0x10041000: ('RAND', 0), 0x10042000: ('GET_VALUE', 0),
    0x10043000: ('GET_VALUE_ARGS', 0),
    0x10051000: ('LT', 0), 0x10052000: ('LE', 0),
    0x10053000: ('GT', 0), 0x10054000: ('GE', 0),
    0x10055000: ('EQ', 0), 0x10056000: ('NE', 0),
    0x10057000: ('AND', 0), 0x10058000: ('OR', 0),
    0x10059000: ('XOR', 0), 0x1005A000: ('NOT', 0),
    0x10061000: ('START_SCRIPT', 2), 0x10062000: ('CALL_SCRIPT', 2),
    0x10064000: ('JUMP', 1), 0x10065000: ('RETURN', 0),
    0x10066000: ('JUMP_IF_ZERO', 1), 0x10067000: ('SIGNAL', 0),
    0x10068000: ('SET_SIGNAL_MASK', 0), 0x10071000: ('EXPLODE', 1),
    0x10082000: ('SET_VALUE', 0), 0x10083000: ('ATTACH_UNIT', 0),
    0x10084000: ('DROP_UNIT', 0),
}


def signed(value):
    return value - 0x100000000 if value & 0x80000000 else value


def decode(data):
    version, nf, np, words, ns, _, function_at, name_at, piece_at, code_at, _ = unpack('<11I', data)
    if version != 4:
        raise FormatError(f'Unsupported COB version {version}')
    if max(nf, np, ns) > 65536 or words > 4 * 1024 * 1024:
        raise FormatError('Excessive COB counts')
    code = list(unpack('<' + 'I' * words, data, code_at))

    def names(at, count):
        values = []
        for i in range(count):
            offset, = unpack('<I', data, at + i * 4)
            span(data, offset, 1)
            end = data.find(b'\0', offset)
            if end < 0:
                raise FormatError('Unterminated COB name')
            values.append(data[offset:end].decode('ascii'))
        if len({x.lower() for x in values}) != len(values):
            raise FormatError('Duplicate COB names')
        return values

    functions = [dict(name=name, address=unpack('<I', data, function_at + i * 4)[0])
                 for i, name in enumerate(names(name_at, nf))]
    pieces = names(piece_at, np)
    instructions = []
    boundaries = set()
    pc = 0
    while pc < words:
        opcode = code[pc]
        if opcode not in OPCODES:
            raise FormatError(f'Unknown opcode {opcode:08x} at word {pc}')
        name, count = OPCODES[opcode]
        if pc + count >= words:
            raise FormatError('Truncated COB instruction')
        args = code[pc + 1:pc + 1 + count]
        if name in ('PUSH_STATIC', 'POP_STATIC') and args[0] >= ns:
            raise FormatError('Static variable out of range')
        if name in ('START_SCRIPT', 'CALL_SCRIPT') and (args[0] >= nf or args[1] > 32):
            raise FormatError('Invalid script call')
        if name in ('MOVE', 'TURN', 'MOVE_NOW', 'TURN_NOW', 'SPIN', 'STOP_SPIN', 'WAIT_TURN', 'WAIT_MOVE'):
            if args[0] >= np or args[1] >= 3:
                raise FormatError('Invalid piece or axis')
        if name in ('HIDE', 'SHOW', 'CACHE', 'DONT_CACHE', 'SHADE', 'DONT_SHADE', 'EMIT_SFX', 'EXPLODE') and args[0] >= np:
            raise FormatError('Invalid piece')
        boundaries.add(pc)
        instructions.append(dict(address=pc, opcode=opcode, name=name, args=args))
        pc += 1 + count
    for function in functions:
        if function['address'] not in boundaries:
            raise FormatError('Function does not start on an instruction')
    for instruction in instructions:
        if instruction['name'] in ('JUMP', 'JUMP_IF_ZERO') and instruction['args'][0] not in boundaries:
            raise FormatError('Jump does not land on an instruction')
    return dict(version=version, sha256=hashlib.sha256(data).hexdigest(), static_count=ns,
                functions=functions, pieces=pieces, code=code, instructions=instructions)


def disassemble(script):
    labels = {f['address']: f['name'] for f in script['functions']}
    lines = []
    for instruction in script['instructions']:
        pc, name, args = instruction['address'], instruction['name'], instruction['args']
        if pc in labels:
            lines += ['', labels[pc] + ':']
        desc = ', '.join(str(signed(x)) for x in args)
        if name in ('START_SCRIPT', 'CALL_SCRIPT'):
            desc += '  ; ' + script['functions'][args[0]]['name']
        if name in ('MOVE', 'TURN', 'MOVE_NOW', 'TURN_NOW', 'SPIN', 'STOP_SPIN', 'WAIT_TURN', 'WAIT_MOVE', 'SHOW', 'HIDE'):
            desc += '  ; ' + script['pieces'][args[0]]
            if len(args) > 1:
                desc += '.' + 'xyz'[args[1]]
        lines.append(f'{pc:06d}  {name:18s} {desc}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file', type=Path)
    parser.add_argument('--output', type=Path, default=Path('local/scripts/armcom'))
    args = parser.parse_args()
    result = decode(args.file.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix('.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    args.output.with_suffix('.asm').write_text(disassemble(result), encoding='utf-8')
    print(json.dumps(dict(functions=result['functions'], pieces=result['pieces'],
                          statics=result['static_count'], opcodes=dict(Counter(i['name'] for i in result['instructions']))), indent=2))


if __name__ == '__main__':
    main()
