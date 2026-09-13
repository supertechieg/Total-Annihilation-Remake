"""COB decoder checks with minimal synthetic binary inputs."""
import struct
import unittest
from cob import decode
from ta_assets import FormatError


def fixture(words):
    code_at = 44
    indexes = code_at + 4 * len(words)
    names = indexes + 4
    pieces = names + 4
    strings = pieces + 4
    return (struct.pack('<11I', 4, 1, 1, len(words), 1, 0, indexes, names, pieces, code_at, strings)
            + struct.pack('<' + 'I' * len(words), *words)
            + struct.pack('<III', 0, strings, strings + 7) + b'Create\0body\0')


class CobTests(unittest.TestCase):
    def test_header_names_and_instructions(self):
        script = decode(fixture([0x10021001, 0xffffffff, 0x10065000]))
        self.assertEqual(script['pieces'], ['body'])
        self.assertEqual(script['functions'], [dict(name='Create', address=0)])
        self.assertEqual([i['address'] for i in script['instructions']], [0, 2])

    def test_jump_into_operand_rejected(self):
        with self.assertRaisesRegex(FormatError, 'Jump'):
            decode(fixture([0x10064000, 1]))

    def test_truncated_instruction_rejected(self):
        with self.assertRaisesRegex(FormatError, 'Truncated'):
            decode(fixture([0x10001000, 0]))

    def test_bad_static_rejected(self):
        with self.assertRaisesRegex(FormatError, 'Static'):
            decode(fixture([0x10021004, 2, 0x10065000]))

    def test_bad_piece_rejected(self):
        with self.assertRaisesRegex(FormatError, 'piece'):
            decode(fixture([0x10006000, 4, 0x10065000]))

    def test_bad_magic_and_unknown_opcode_rejected(self):
        with self.assertRaisesRegex(FormatError, 'version'):
            decode(bytes(44))
        with self.assertRaisesRegex(FormatError, 'Unknown opcode'):
            decode(fixture([0xdeadbeef]))


if __name__ == '__main__':
    unittest.main()
