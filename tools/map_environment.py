"""Recovered map environment selection and gravity conversion."""
from weapon_math import extended_product_integer


def gravity_raw(version, header_gravity=0, override=-1):
    value = override if version >= 0x2000 and override >= 0 else header_gravity
    if value == 0 and not (version >= 0x2000 and override >= 0):
        return 8155
    # First multiply is an exact power-of-two scaling of a signed32 integer;
    # second uses the executable's binary64 1/900 constant at x87 precision.
    result = extended_product_integer(float(value) * 65536.0, 0.0011111111111111111)
    result &= 0xffffffff
    return result - 0x100000000 if result >= 0x80000000 else result


def environment(header, descriptor):
    version = header[0]
    legacy = version < 0x2000
    return dict(gravity_raw_per_tick=gravity_raw(version, header[13] if legacy else 0, int(descriptor.get('gravity', '-1'))),
                min_wind=int(descriptor.get('minwindspeed', '-1')) if not legacy and int(descriptor.get('minwindspeed', '-1')) >= 0 else (header[10] if legacy else 100),
                max_wind=int(descriptor.get('maxwindspeed', '-1')) if not legacy and int(descriptor.get('maxwindspeed', '-1')) >= 0 else (header[11] if legacy else 2000))
