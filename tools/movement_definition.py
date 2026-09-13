"""Original 0x440340 field conversions after movement-class selection."""


def movement_definition(fields):
    def short(key, default):
        return (int(fields.get(key, default)) + 32768) % 65536 - 32768

    slope = int(fields.get('maxslope', 255)) & 255
    bad = int(fields.get('badslope', slope >> 1)) & 255
    water = int(fields.get('maxwaterslope', 255)) & 255
    water_bad = int(fields.get('badwaterslope', water >> 1)) & 255
    return dict(footprintx=short('footprintx', 0), footprintz=short('footprintz', 0),
                maxwaterdepth=short('maxwaterdepth', 10000),
                minwaterdepth=short('minwaterdepth', -10000),
                maxslope=min(slope, water), badslope=min(bad, slope, water),
                maxwaterslope=water, badwaterslope=min(water_bad, water))
