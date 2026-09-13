import unittest
from tdf import parse
from ta_assets import FormatError


class TdfTests(unittest.TestCase):
    def test_nested_names_do_not_collide(self):
        result = parse('[SIDE]{name=ARM;[COMMANDER]{name=ARMCOM;}}[OTHER]{name=CORE;}')
        self.assertEqual(result['side']['name'], 'ARM')
        self.assertEqual(result['side']['commander']['name'], 'ARMCOM')
        self.assertEqual(result['other']['name'], 'CORE')

    def test_comments_and_windows_newlines(self):
        self.assertEqual(parse('// header\r\n[UnitInfo] /* before */ {\r\n// line\r\nName=Solar; /* end */ }'),
                         {'unitinfo': {'name': 'Solar'}})

    def test_quoted_delimiters_and_empty(self):
        self.assertEqual(parse('[A]{name="a;b}c";empty=;path=anims/foo.gaf;}')['a'],
                         {'name': 'a;b}c', 'empty': '', 'path': 'anims/foo.gaf'})

    def test_provisional_duplicate_policy(self):
        self.assertEqual(parse('[A]{x=1;}[a]{x=2;y=3;}'), {'a': {'x': '2', 'y': '3'}})

    def test_malformed_input(self):
        for text in ['[A]{x=1', '[A]{x=1;', '[A]x=1;', '[A]{x=1}', '}', '/*', '[A]{=1;}', '[A]{x="bad;}']:
            with self.subTest(text=text), self.assertRaises(FormatError):
                parse(text)

    def test_depth_bound(self):
        with self.assertRaises(FormatError):
            parse('[a]{' * 70 + '}' * 70)


if __name__ == '__main__':
    unittest.main()
