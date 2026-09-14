"""TNT 0x2000 map feature loading (0x483a99..0x483b4e) through placement 0x423c50 and removal 0x4246b0.

Pass 1 writes void code 0xfffc for every attribute word 0xfffc. Pass 2 places, in row-major order, every attribute
word below the map's feature count. Placement rejects footprints past the map edge, removes whatever covers its
cells (failing, after earlier removals, on void or indestructible features), needs a free record from the 0x800
instance pool for features with an object, then writes the anchor code and 0xfffe continuations.
"""
NONE, CONTINUATION, VOID = 0xffff, 0xfffe, 0xfffc
POOL = 0x800


def signed16(value):
    value &= 0xffff
    return value - 0x10000 if value >= 0x8000 else value


class FeatureGrid:
    def __init__(self, width, height, definitions):
        """definitions: dicts with footprintx, footprintz, indestructible and object (False for flag bit 0 features)."""
        self.width, self.height = width, height
        self.definitions = definitions
        self.codes = [NONE] * (width * height)
        self.rows = [0] * (width * height)
        self.columns = [0] * (width * height)
        self.instance = [False] * (width * height)
        self.live = 0

    def remove(self, cell):
        if self.codes[cell] == CONTINUATION:
            cell -= self.rows[cell] * self.width + self.columns[cell]
        code = self.codes[cell]
        if code >= 0xfffb:
            return False
        definition = self.definitions[code]
        if definition['indestructible']:
            return False
        if self.instance[cell]:
            self.live -= 1
        self.codes[cell] = NONE
        self.instance[cell] = False
        for dz in range(signed16(definition['footprintz'])):
            for dx in range(signed16(definition['footprintx'])):
                covered = cell + dz * self.width + dx
                if self.codes[covered] == CONTINUATION:
                    self.codes[covered] = NONE
                    self.instance[covered] = False
        return True

    def place(self, cell, code):
        if code == NONE:
            return False
        if code == VOID:
            self.codes[cell] = VOID
            return False
        definition = self.definitions[code]
        x, z = cell % self.width, cell // self.width
        fx, fz = signed16(definition['footprintx']), signed16(definition['footprintz'])
        if x + fx > self.width or z + fz > self.height:
            return False
        for dz in range(fz):
            for dx in range(fx):
                covered = (z + dz) * self.width + x + dx
                if self.codes[covered] != NONE and not self.remove(covered):
                    return False
        has_object = definition['object']
        if has_object:
            if self.live >= POOL:
                return False
            self.live += 1
        self.codes[cell] = code
        self.instance[cell] = has_object
        for dz in range(max(0, fz)):
            for dx in range(max(0, fx)):
                if dx or dz:
                    covered = (z + dz) * self.width + x + dx
                    self.codes[covered] = CONTINUATION
                    self.rows[covered] = dz
                    self.columns[covered] = dx
                    self.instance[covered] = False
        return True


def load(width, height, attributes, definitions):
    """attributes: the TNT attribute feature word per cell. Returns the resulting FeatureGrid."""
    grid = FeatureGrid(width, height, definitions)
    for cell, code in enumerate(attributes):
        if code == VOID:
            grid.place(cell, VOID)
    for cell, code in enumerate(attributes):
        if code < len(definitions):
            grid.place(cell, code)
    return grid


def blocking(grid, blocking_flags):
    """0x47de60 feature branch: empty cells pass, loaded features pass unless flagged blocking, every other code
    (void, reserved, out of range) blocks; continuations use their anchor's code."""
    result = bytearray(grid.width * grid.height)
    for cell, code in enumerate(grid.codes):
        if code == CONTINUATION:
            code = grid.codes[cell - grid.rows[cell] * grid.width - grid.columns[cell]]
        if code != NONE and not (code < len(blocking_flags) and not blocking_flags[code]):
            result[cell] = 1
    return bytes(result)
