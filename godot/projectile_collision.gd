extends RefCounted

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
