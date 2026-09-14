extends RefCounted

const UNITS_ONLY := 0x4000
const GROUND_BOUNCE := 0x8000
const WATER_WEAPON := 0x10000

static func cell_index(position: Array, width: int, depth: int) -> int:
	var x := int(position[0]) >> 20
	var z := int(position[2]) >> 20
	return z * width + x if x >= 0 and z >= 0 and x < width and z < depth else -1

static func unit_target(y: int, owner: int, occupants: Array) -> int:
	for slot in range(2):
		var unit: Dictionary = occupants[slot]
		if int(unit.id) == 0 or int(unit.owner) == owner:
			continue
		if slot == 0:
			if y < int(unit.top):
				return int(unit.id)
		elif y >= int(unit.bottom) and y <= int(unit.top):
			return int(unit.id)
	return 0

static func signed16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value >= 0x8000 else value

## Terrain, feature and water branch of original 0x49b090 after both unit slots miss.
## cell: {low, high, code}; anchor_code is the redirected anchor's code for 0xfffe continuations.
static func terrain_contact(input: Dictionary) -> Dictionary:
	var cell: Dictionary = input.cell
	var low := int(cell.low)
	@warning_ignore("integer_division")
	var result := {"impact": false, "velocity_y": int(input.velocity_y), "cache": input.cache.duplicate(),
		"surface": (int(cell.high) + low) / 2}
	var flags := int(input.flags)
	if flags & UNITS_ONLY:
		return result
	var y := signed16(int(input.position[1]) >> 16)
	var heights: Array = input.feature_heights
	var feature_height := -1
	var code := int(cell.code)
	if code < 0xfffb:
		if code < int(input.feature_count):
			feature_height = int(heights[code]) if code < heights.size() else 0
	elif code == 0xfffe:
		# The redirected anchor index is not checked against the loaded feature count.
		var anchor := int(input.anchor_code)
		if anchor < 0xfffb:
			feature_height = int(heights[anchor]) if anchor < heights.size() else 0
	if feature_height >= 0 and y < feature_height + low:
		var sx := signed16(int(input.position[0]) >> 16)
		var sz := signed16(int(input.position[2]) >> 16)
		# Signed division by 16 truncating toward zero, as the original shift-with-bias does.
		sx = (sx + ((sx >> 31) & 15)) >> 4
		sz = (sz + ((sz >> 31) & 15)) >> 4
		if int(result.cache[0]) != sx or int(result.cache[1]) != sz:
			result.cache = [sx, sz]
			result.impact = true
			return result
	if y < low:
		if flags & GROUND_BOUNCE:
			var vertical := int(result.velocity_y) >> 2
			result.velocity_y = -vertical
			return result
	else:
		if flags & WATER_WEAPON or int(input.sea) <= y or int(input.lava) != 0:
			return result
	result.impact = true
	return result
