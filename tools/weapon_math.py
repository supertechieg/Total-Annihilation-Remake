"""Weapon scalar conversion using the loader's binary64 input and x87 precision."""
from fractions import Fraction
import math
import re
import struct


def minimum_barrel_angle(text='-11.25'):
    value = float(text)
    if not math.isfinite(value):
        raise ValueError('Non-finite weapon angle')
    return struct.unpack('<f', struct.pack('<f', value * 0.017453292519943278))[0]


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
    # Original numeric parser accepts the leading number in shipped typos (13O).
    prefix = re.match(r'\s*([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)', str(text))
    value = float(prefix.group(1) if prefix else text)
    if not math.isfinite(value):
        raise ValueError('Non-finite weapon scalar')
    if kind not in ('velocity', 'start_velocity', 'acceleration', 'reload', 'burst_rate', 'turn_rate'):
        raise ValueError(f'Unknown weapon scalar: {kind}')
    multiplier = 1.0 / 30.0 if kind == 'turn_rate' else 65536.0 / 900.0 if kind == 'acceleration' else 65536.0 / 30.0 if kind in ('velocity', 'start_velocity') else 30.0
    result = extended_product_integer(value, multiplier)
    if kind in ('reload', 'burst_rate', 'turn_rate'):
        return result & 0xffff
    result &= 0xffffffff
    return result - 0x100000000 if result >= 0x80000000 else result


def weapon_runtime(definition):
    return {
        'velocity_raw_per_tick': scaled_weapon_value(definition.get('weaponvelocity', '0'), 'velocity'),
        'start_velocity_raw_per_tick': scaled_weapon_value(definition.get('startvelocity', '0'), 'start_velocity'),
        'acceleration_raw_per_tick_squared': scaled_weapon_value(definition.get('weaponacceleration', '0'), 'acceleration'),
        'turn_raw_per_tick': scaled_weapon_value(definition.get('turnrate', '0'), 'turn_rate'),
        'reload_ticks': scaled_weapon_value(definition.get('reloadtime', '0'), 'reload'),
        'burst_interval_ticks': scaled_weapon_value(definition.get('burstrate', '0'), 'burst_rate'),
        'minimum_barrel_angle': minimum_barrel_angle(definition.get('minbarrelangle', '-11.25')),
    }
