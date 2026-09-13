"""Weapon scalar conversion using the loader's binary64 input and x87 precision."""
from fractions import Fraction
import math


def extended_product_integer(value, multiplier):
    product = Fraction.from_float(value) * Fraction.from_float(multiplier)
    if not product:
        return 0
    sign = -1 if product < 0 else 1
    product = abs(product)
    exponent = product.numerator.bit_length() - product.denominator.bit_length()
    power = Fraction(2) ** exponent
    if product < power:
        exponent -= 1
    quantum = Fraction(2) ** (exponent - 63)
    scaled = product / quantum
    quotient, remainder = divmod(scaled.numerator, scaled.denominator)
    if 2 * remainder > scaled.denominator or (2 * remainder == scaled.denominator and quotient & 1):
        quotient += 1
    return sign * int(quotient * quantum)


def scaled_weapon_value(text, kind):
    value = float(text)
    if not math.isfinite(value):
        raise ValueError('Non-finite weapon scalar')
    if kind not in ('velocity', 'reload', 'burst_rate'):
        raise ValueError(f'Unknown weapon scalar: {kind}')
    result = extended_product_integer(value, 65536.0 / 30.0 if kind == 'velocity' else 30.0)
    if kind != 'velocity':
        return result & 0xffff
    result &= 0xffffffff
    return result - 0x100000000 if result >= 0x80000000 else result


def weapon_runtime(definition):
    return {
        'velocity_raw_per_tick': scaled_weapon_value(definition.get('weaponvelocity', '0'), 'velocity'),
        'reload_ticks': scaled_weapon_value(definition.get('reloadtime', '0'), 'reload'),
        'burst_interval_ticks': scaled_weapon_value(definition.get('burstrate', '0'), 'burst_rate'),
    }
