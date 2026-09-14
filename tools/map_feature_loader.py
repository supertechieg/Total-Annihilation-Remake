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


def msvc_atoi(text):
    """MSVC atol as used by the TDF integer accessor: skip whitespace, optional sign, decimal digits, wrap to int32."""
    text = str(text).lstrip(' \t\n\r\v\f')
    sign = 1
    if text[:1] in '+-' and text:
        sign = -1 if text[0] == '-' else 1
        text = text[1:]
    value = 0
    for character in text:
        if not character.isdigit() or not character.isascii():
            break
        value = (value * 10 + int(character)) & 0xffffffff
    value = (value * sign) & 0xffffffff
    return value - 0x100000000 if value >= 0x80000000 else value


def schema_features(schema):
    """0x436c30: the chosen schema's [features] children in file order as (name, xpos, zpos); XPos/ZPos default -1 and
    a negative coordinate (or a missing name) blanks the entry, which 0x423160 then skips. Names keep 127 characters."""
    section = next((value for key, value in schema.items() if key.lower() == 'features' and isinstance(value, dict)), {})
    entries = []
    for child in section.values():
        if not isinstance(child, dict):
            continue
        fields = {key.lower(): value for key, value in child.items()}
        name = str(fields.get('featurename', ''))[:0x7f]
        x = msvc_atoi(fields['xpos']) if 'xpos' in fields else -1
        z = msvc_atoi(fields['zpos']) if 'zpos' in fields else -1
        entries.append(('' if x < 0 or z < 0 else name, x, z))
    return entries


def trunc_half(value):
    return int(value / 2)


def place_schema_features(grid, entries, extra_definitions):
    """0x423160 after TNT pass 2: case-insensitive name lookup (appending unknown definitions by name, as 0x4224b0 does),
    2D features anchor at (x, z) and 3D features at (x - fx/2, z - fz/2) truncated; placement uses owner 10.
    An anchor outside the map passes a null cell in the original (undefined); it is skipped and returned."""
    skipped = []
    for name, x, z in entries:
        if not name:
            continue
        code = next((index for index, definition in enumerate(grid.definitions) if definition['name'].lower() == name.lower()), None)
        if code is None:
            if name.lower() not in extra_definitions:
                raise KeyError(f'schema feature definition not found: {name}')
            grid.definitions.append(dict(extra_definitions[name.lower()], name=name))
            code = len(grid.definitions) - 1
        definition = grid.definitions[code]
        if definition['object']:
            x -= trunc_half(signed16(definition['footprintx']))
            z -= trunc_half(signed16(definition['footprintz']))
        if not (0 <= x < grid.width and 0 <= z < grid.height):
            skipped.append((name, x, z))
            continue
        grid.place(z * grid.width + x, code)
    return skipped


def load(width, height, attributes, definitions, schema_entries=(), extra_definitions=None):
    """attributes: the TNT attribute feature word per cell; schema_entries from schema_features. Returns the FeatureGrid
    (definitions appended by schema features extend grid.definitions)."""
    grid = FeatureGrid(width, height, list(definitions))
    count = len(definitions)
    for cell, code in enumerate(attributes):
        if code == VOID:
            grid.place(cell, VOID)
    for cell, code in enumerate(attributes):
        if code < count:
            grid.place(cell, code)
    grid.skipped_schema_features = place_schema_features(grid, schema_entries, extra_definitions or {})
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
