import unittest
from weapon_math import scaled_weapon_value, weapon_runtime, minimum_barrel_angle


class WeaponMathTests(unittest.TestCase):
    def test_original_emg_values(self):
        self.assertEqual(weapon_runtime({'weaponvelocity': '300', 'reloadtime': '.4', 'burstrate': '.1'}),
                         dict(turn_raw_per_tick=0, start_velocity_raw_per_tick=0, acceleration_raw_per_tick_squared=0, velocity_raw_per_tick=655359, reload_ticks=12, burst_interval_ticks=3, duration_ticks=0, minimum_barrel_angle=-0.19634954631328583))

    def test_extended_precision_timing_boundary(self):
        self.assertEqual(scaled_weapon_value('.3', 'reload'), 8)
        self.assertEqual(scaled_weapon_value('1.2', 'reload'), 35)
        self.assertEqual(scaled_weapon_value('.4', 'reload'), 12)

    def test_signed_conversion_and_word_storage(self):
        self.assertEqual(scaled_weapon_value('-.3', 'velocity'), -655)
        self.assertEqual(scaled_weapon_value('-.3', 'reload'), 65528)

    def test_missing_values_use_native_defaults(self):
        self.assertEqual(weapon_runtime({}), dict(turn_raw_per_tick=0, start_velocity_raw_per_tick=0, acceleration_raw_per_tick_squared=0, velocity_raw_per_tick=0, reload_ticks=0, burst_interval_ticks=0, duration_ticks=0,
                                               minimum_barrel_angle=-0.19634954631328583))

    def test_barrel_angle_float32(self):
        self.assertEqual(minimum_barrel_angle('0'), 0.0)
        self.assertEqual(minimum_barrel_angle('90'), 1.5707963705062866)
        self.assertEqual(weapon_runtime({'minbarrelangle': '-45'})['minimum_barrel_angle'], -0.7853981852531433)

    def test_original_rocket_scalars_and_shipped_typo(self):
        result = weapon_runtime({'startvelocity': '250', 'weaponacceleration': '120'})
        self.assertEqual(result['start_velocity_raw_per_tick'], 546133)
        self.assertEqual(result['acceleration_raw_per_tick_squared'], 8738)
        self.assertEqual(scaled_weapon_value('13O', 'acceleration'), 946)

    def test_beam_duration_truncates_to_word_ticks(self):
        self.assertEqual(scaled_weapon_value('.02', 'duration'), 0)
        self.assertEqual(scaled_weapon_value('.04', 'duration'), 1)
        self.assertEqual(scaled_weapon_value('.03333333333333333', 'duration'), 0)
        self.assertEqual(scaled_weapon_value('-.1', 'duration'), 65533)

    def test_turn_rate_extended_precision(self):
        self.assertEqual(scaled_weapon_value('30000', 'turn_rate'), 999)
        self.assertEqual(scaled_weapon_value('33000', 'turn_rate'), 1099)
        self.assertEqual(scaled_weapon_value('30', 'turn_rate'), 0)
        self.assertEqual(scaled_weapon_value('1966080', 'turn_rate'), 65535)

    def test_invalid_inputs(self):
        for value in ['nan', 'inf', '-inf', 'invalid']:
            with self.assertRaises(ValueError):
                scaled_weapon_value(value, 'velocity')
            with self.assertRaises(ValueError):
                minimum_barrel_angle(value)
        with self.assertRaises(ValueError):
            scaled_weapon_value('1', 'unknown')


if __name__ == '__main__':
    unittest.main()
