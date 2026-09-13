import unittest
from weapon_math import scaled_weapon_value, weapon_runtime


class WeaponMathTests(unittest.TestCase):
    def test_original_emg_values(self):
        self.assertEqual(weapon_runtime({'weaponvelocity': '300', 'reloadtime': '.4', 'burstrate': '.1'}),
                         dict(velocity_raw_per_tick=655359, reload_ticks=12, burst_interval_ticks=3))

    def test_extended_precision_timing_boundary(self):
        self.assertEqual(scaled_weapon_value('.3', 'reload'), 8)
        self.assertEqual(scaled_weapon_value('1.2', 'reload'), 35)
        self.assertEqual(scaled_weapon_value('.4', 'reload'), 12)

    def test_signed_conversion_and_word_storage(self):
        self.assertEqual(scaled_weapon_value('-.3', 'velocity'), -655)
        self.assertEqual(scaled_weapon_value('-.3', 'reload'), 65528)

    def test_missing_values_are_zero(self):
        self.assertEqual(set(weapon_runtime({}).values()), {0})

    def test_invalid_inputs(self):
        for value in ['nan', 'inf', '-inf', 'invalid']:
            with self.assertRaises(ValueError):
                scaled_weapon_value(value, 'velocity')
        with self.assertRaises(ValueError):
            scaled_weapon_value('1', 'unknown')


if __name__ == '__main__':
    unittest.main()
