extends RefCounted
## Splash damage to map features: the feature pass of 0x49a120 and per-feature damage 0x4244b0. See analysis/FEATURE_DAMAGE.md.
## Inputs mirror the original 13-byte cells (+4 height, +8 code, +0xa word, +0xc flag bit 0 = instance record).
const NONE_LIMIT := 0xfffb
const CONTINUATION := 0xfffe
const INDESTRUCTIBLE := 0x200
const FLAMABLE := 0x10
const NO_OBJECT := 0x1
const UNITS_ONLY := 0x4000

static func signed16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value >= 0x8000 else value

static func signed32(value: int) -> int:
	value &= 0xffffffff
	return value - 0x100000000 if value >= 0x80000000 else value

## cdq / and 15 / add / sar 4: division by 16 truncating toward zero.
static func div16(value: int) -> int:
	return (value + (15 if value < 0 else 0)) >> 4

## 0x485070: bilinear terrain height at a 16.16 position, -1 outside the interior cells.
static func height(heights: PackedByteArray, width: int, rows: int, x_raw: int, z_raw: int) -> int:
	var hx := signed16(x_raw >> 16)
	var hz := signed16(z_raw >> 16)
	var cx := hx >> 4
	var cz := hz >> 4
	var fx := hx & 0xf
	var fz := hz & 0xf
	if cx < 0 or cx + 1 >= width or cz < 0 or cz + 1 >= rows:
		return -1
	var index := cz * width + cx
	var h00 := int(heights[index])
	var h10 := int(heights[index + 1])
	var h01 := int(heights[index + width])
	var h11 := int(heights[index + width + 1])
	var top := trunc_div16((h10 - h00) * fx) + h00
	var bottom := trunc_div16((h11 - h01) * fx) + h01
	return trunc_div16((bottom - top) * fz) + top

static func trunc_div16(value: int) -> int:
	return (value + (15 if value < 0 else 0)) >> 4

## 0x49a850 / the 2D-feature branch: fsqrt of int32 squares truncated by ftol, keeping the signed high word.
static func distance(a: Array, b: Array) -> int:
	var squared := 0
	for axis in range(3):
		var delta := signed32(int(a[axis]) - int(b[axis]))
		squared += delta * delta
	var root := int(sqrt(float(squared)))
	while root * root > squared:
		root -= 1
	while (root + 1) * (root + 1) <= squared:
		root += 1
	if root >= 0x80000000:
		root = 0x80000000
	return signed16(root >> 16)

## Grid interface (FeatureWorld or ArrayGrid): width, depth, heights, code_at, word_at, bits_at, set_word,
## definition_of(code) -> {footprintx, footprintz, damage, flags}, instance_position/instance_anchor/instance_damage/set_instance_damage(index).
## Returns calls in order: hits [anchor, x, z], replaced [x, z] (0x423550 with parameter 0) and ignited [x, z] (0x4233a0).
static func splash(grid, weapon: Dictionary, position: Array, game_flags: int) -> Dictionary:
	var result := {"hits": [], "replaced": [], "ignited": []}
	if int(weapon.get("flags", 0)) & UNITS_ONLY:
		return result
	var width := int(grid.width)
	var rows := int(grid.depth)
	var radius := (int(weapon.area) & 0xffff) >> 1
	var reach := (radius >> 4) + 1
	var cx := div16(signed16(int(position[0]) >> 16))
	var cz := div16(signed16(int(position[2]) >> 16))
	var seen: Array = []
	for z in range(maxi(0, cz - reach), mini(rows, cz + reach)):
		for x in range(maxi(0, cx - reach), mini(width, cx + reach)):
			var cell := z * width + x
			var ax := x
			var az := z
			var anchor := cell
			if int(grid.code_at(cell)) == CONTINUATION:
				var offsets := int(grid.word_at(cell))
				ax = x - ((offsets >> 8) & 0xff)
				az = z - (offsets & 0xff)
				anchor = az * width + ax
			var code := int(grid.code_at(anchor))
			if code >= NONE_LIMIT:
				continue
			var definition: Dictionary = grid.definition_of(code)
			var gap: int
			# The distance branch reads the current cell's instance flag and word, not the anchor's.
			if int(grid.bits_at(cell)) & 1:
				gap = distance(position, grid.instance_position(int(grid.word_at(cell))))
			else:
				# 0x421eb0: current cell with the anchor definition's footprint, height from 0x485070.
				var px := signed32((signed16(int(definition.footprintx)) + 2 * x) << 19)
				var pz := signed32((signed16(int(definition.footprintz)) + 2 * z) << 19)
				gap = distance(position, [px, signed32(height(grid.heights, width, rows, px, pz) << 16), pz])
			if gap >= radius or seen.has(anchor):
				continue
			if seen.size() < 64:
				seen.append(anchor)
			result.hits.append([anchor, ax, az])
			damage(grid, anchor, ax, az, weapon, game_flags, result)
	return result

## 0x4244b0(cell, x, z, weapon) in a single-player game (network state other than 3).
static func damage(grid, anchor: int, x: int, z: int, weapon: Dictionary, game_flags: int, result: Dictionary) -> void:
	if (game_flags & 8) == 0:
		return
	var code := int(grid.code_at(anchor))
	if code >= NONE_LIMIT:
		return
	var definition: Dictionary = grid.definition_of(code)
	var flags := int(definition.flags)
	if flags & INDESTRUCTIBLE:
		return
	var amount := int(weapon.default) & 0xffff
	var has_instance := (int(grid.bits_at(anchor)) & 1) != 0
	if flags & FLAMABLE and int(weapon.get("firestarter", 0)) & 0xff and not has_instance:
		result.ignited.append([x, z])
		return
	if has_instance:
		if flags & NO_OBJECT:
			return
		var index := int(grid.word_at(anchor))
		if grid.instance_anchor(index) != Vector2i(x, z):
			return
		var taken := (int(grid.instance_damage(index)) + amount) & 0xffff
		grid.set_instance_damage(index, taken)
		if taken >= (int(definition.damage) & 0xffff):
			result.replaced.append([x, z])
		return
	var total := amount + (int(grid.word_at(anchor)) & 0xffff)
	if total >= (int(definition.damage) & 0xffff):
		result.replaced.append([x, z])
	else:
		grid.set_word(anchor, total & 0xffff)

## Plain arrays mirroring the original cells, for native comparisons and tests.
class ArrayGrid:
	extends RefCounted
	var width: int
	var depth: int
	var heights: PackedByteArray
	var codes: Array
	var words: Array
	var bits: Array
	var definitions: Array
	var instances: Array
	func _init(size_x: int, size_z: int, height_bytes: PackedByteArray, cell_codes: Array, cell_words: Array, cell_bits: Array, feature_definitions: Array, feature_instances: Array) -> void:
		width = size_x
		depth = size_z
		heights = height_bytes
		codes = cell_codes
		words = cell_words
		bits = cell_bits
		definitions = feature_definitions
		instances = feature_instances
	func code_at(cell: int) -> int:
		return int(codes[cell])
	func word_at(cell: int) -> int:
		return int(words[cell])
	func bits_at(cell: int) -> int:
		return int(bits[cell])
	func set_word(cell: int, value: int) -> void:
		words[cell] = value
	func definition_of(code: int) -> Dictionary:
		return definitions[code]
	func instance_position(index: int) -> Array:
		return instances[index].position
	func instance_anchor(index: int) -> Vector2i:
		return Vector2i(int(instances[index].x), int(instances[index].z))
	func instance_damage(index: int) -> int:
		return int(instances[index].damage)
	func set_instance_damage(index: int, value: int) -> void:
		instances[index].damage = value