extends RefCounted
const Float = preload("res://upkeep_gate.gd")

static func calculate(metal: PackedByteArray, map_width: int, map_height: int, footprint: Rect2i, scale: float, previous := 0.0) -> float:
	scale = Float.float32(scale)
	if scale <= 0:
		return Float.float32(previous)
	var total := 0
	for z in range(footprint.position.y, footprint.end.y):
		for x in range(footprint.position.x, footprint.end.x):
			if x >= 0 and x < map_width and z >= 0 and z < map_height:
				total = (total + int(metal[z * map_width + x]) + 1) & 65535
	# The original shifts the sum into a signed int32, then scales by 1/65536.
	if total >= 32768:
		total -= 65536
	return Float.float32(total * scale)
