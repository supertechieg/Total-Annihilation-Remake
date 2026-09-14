extends RefCounted
## 2D map feature sprites: the shared per-type GAF animation step (0x4b8b90, stepped by 0x424050) and the map-draw
## placement of 0x46a610. See analysis/MAP_FEATURE_SPRITES.md.

## Shared animation state for one feature type, starting at frame 0.
## The initial counter is taken as frame 0's duration (the setup routine was not traced).
static func start(durations: Array) -> Dictionary:
	return {"active": not durations.is_empty(), "index": 0, "counter": int(durations[0]) & 0xffff if not durations.is_empty() else 0}

## 0x4b8b90: counters of 2 or more count down; otherwise advance, wrapping when the GAF entry loops and stopping
## (index left at the frame count) when it does not. Returns true when the frame changed or the sequence ended.
static func step(state: Dictionary, durations: Array, loop: bool) -> bool:
	if not bool(state.active):
		return false
	if (int(state.counter) & 0xffff) >= 2:
		state.counter = int(state.counter) - 1
		return false
	state.index = int(state.index) + 1
	if (int(state.index) & 0xffff) >= durations.size():
		if loop:
			state.index = 0
		else:
			state.active = false
			return true
	state.counter = int(durations[int(state.index)]) & 0xffff
	return true

## 0x46a610 world-space anchor (before view scrolling and the 128/32 pixel interface offsets): the footprint centre,
## lifted by the anchor cell's four corner heights summed and shifted right by 3 (half their average).
static func anchor(heights: PackedByteArray, width: int, rows: int, cell_x: int, cell_z: int, footprint_x: int, footprint_z: int) -> Vector2i:
	var sum := 0
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var x := mini(cell_x + offset.x, width - 1)
		var z := mini(cell_z + offset.y, rows - 1)
		sum += int(heights[z * width + x])
	# sar1(cdq(s16 footprint << 4)): truncating half of footprint * 16.
	return Vector2i(cell_x * 16 + int(float(signed16(footprint_x) * 16) / 2.0), cell_z * 16 + int(float(signed16(footprint_z) * 16) / 2.0) - (sum >> 3))

static func signed16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value >= 0x8000 else value
