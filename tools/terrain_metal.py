"""Reconstruct the original indestructible-feature metal overlay."""


def feature_metal(width, height, base, placements):
    """Placements supply loaded feature fields; later row-major anchors overwrite."""
    result = bytearray(base)
    if len(result) != width * height:
        raise ValueError('Metal map size differs from dimensions')
    for feature in sorted(placements, key=lambda item: item['z'] * width + item['x']):
        metal = int(feature['metal']) & 65535
        if not feature['indestructible'] or metal == 0:
            continue
        for z in range(feature['z'], feature['z'] + feature['height']):
            for x in range(feature['x'], feature['x'] + feature['width']):
                if 0 <= x < width and 0 <= z < height:
                    result[z * width + x] = metal & 255
    return bytes(result)
