import unittest
from map_environment import gravity_raw, environment


class MapEnvironmentTests(unittest.TestCase):
    def test_legacy_default(self):
        self.assertEqual(gravity_raw(0x1020), 8155)

    def test_legacy_ignores_override(self):
        self.assertEqual(gravity_raw(0x1020, 60, 112), 4369)

    def test_descriptor_zero_is_not_default(self):
        self.assertEqual(gravity_raw(0x2000, 0, 0), 0)

    def test_comet_catcher(self):
        header = [0x2000] + [0] * 15
        self.assertEqual(environment(header, {'gravity': '60', 'minwindspeed': '10', 'maxwindspeed': '15'}),
                         dict(gravity_raw_per_tick=4369, min_wind=10, max_wind=15))

    def test_missing_modern_descriptor(self):
        self.assertEqual(environment([0x2000] + [0] * 15, {}),
                         dict(gravity_raw_per_tick=8155, min_wind=100, max_wind=2000))

    def test_legacy_environment(self):
        header = [0x1020] + [0] * 15
        header[10], header[11], header[13] = 20, 40, 112
        self.assertEqual(environment(header, {'gravity': '60', 'minwindspeed': '1', 'maxwindspeed': '2'}),
                         dict(gravity_raw_per_tick=8155, min_wind=20, max_wind=40))


if __name__ == '__main__':
    unittest.main()
