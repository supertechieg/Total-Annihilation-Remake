"""Reconstruct the static feature-blocking cells consulted by original predicate 0x47de60."""


def blocking_flag(fields):
    """Feature loader stores the low bit of integer TDF field 'blocking', default 0, as flag 0x40."""
    return int(fields.get('blocking', '0')) & 1


def feature_blocking(width, height, placements):
    """Return one byte per cell: 1 when a blocking feature's anchor or continuation cell covers it.

    Placement writes the feature index at the anchor and 0xfffe continuation markers across
    footprintx by footprintz; the predicate resolves continuations back to the anchor's flag.
    Callers must supply non-overlapping, in-bounds placements (original overlap resolution is unknown).
    """
    result = bytearray(width * height)
    for feature in placements:
        if not feature['blocking']:
            continue
        x, z = feature['x'], feature['z']
        if not (0 <= x < width and 0 <= z < height):
            raise ValueError('Feature anchor lies outside the map')
        result[z * width + x] = 1
        for zz in range(z, z + feature['height']):
            for xx in range(x, x + feature['width']):
                if not (0 <= xx < width and 0 <= zz < height):
                    raise ValueError('Feature footprint crosses map boundary')
                result[zz * width + xx] = 1
    return bytes(result)
