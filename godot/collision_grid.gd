extends RefCounted
const Ground = preload("res://ground_motion.gd")
## Unit slots and yard maps; overlap callbacks remain separate.
var width: int
var depth: int
var cells: Array = []
var terrain_flags: Array = []

static func unit_rect(position_raw: Array, footprint: Vector2i) -> Rect2i:
	var origin := Vector2i.ZERO
	for axis in range(2):
		origin[axis] = Ground.signed32(int(position_raw[axis]) - footprint[axis] * 524288 + 524288) >> 20
	return Rect2i(origin, footprint)

func _init(map_width: int, map_depth: int) -> void:
	width = map_width
	depth = map_depth
	for index in range(width * depth):
		cells.append([0, 0])
		terrain_flags.append(0)

func insert_unit(id: int, rect: Rect2i, slot: int, units: Dictionary, yard: Array = [], yard_open := false) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x >= width or rect.end.y >= depth:
		return false
	if not yard.is_empty():
		slot = 0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not yard.is_empty():
				var value := int(yard[(z - rect.position.y) * rect.size.x + x - rect.position.x])
				if (value & 1) != 0:
					terrain_flags[z * width + x] |= 2
				if (value & (2 if yard_open else 4)) == 0:
					continue
			var cell: Array = cells[z * width + x]
			var previous := int(cell[slot])
			if previous == 0:
				cell[slot] = id
			elif bool(units[previous].replaceable):
				units[previous].flags |= 0x8000000
				units[id].flags |= 0x4000000
				cell[slot] = id
			else:
				units[previous].flags |= 0x4000000
				units[id].flags |= 0x8000000
	return true

func remove_unit(id: int, rect: Rect2i, slot: int, units: Dictionary, was_inserted: bool, yard: Array = []) -> void:
	if not yard.is_empty():
		slot = 0
	if was_inserted:
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not yard.is_empty() and (int(yard[(z - rect.position.y) * rect.size.x + x - rect.position.x]) & 1) != 0:
					terrain_flags[z * width + x] &= ~2
				if int(cells[z * width + x][slot]) == id:
					cells[z * width + x][slot] = 0
	units[id].flags &= ~0xc000000

func move_unit(id: int, position_raw: Array, slot: int, units: Dictionary) -> void:
	var unit: Dictionary = units[id]
	var previous: Rect2i = unit.rect
	var next := unit_rect([position_raw[0], position_raw[2]], previous.size)
	if next.position != previous.position or slot != int(unit.slot):
		remove_unit(id, previous, int(unit.slot), units, unit.inserted, unit.get("yard", []))
		unit.rect = next
		unit.slot = slot
		unit.flags = (int(unit.flags) & ~3) | (slot + 1)
		unit.inserted = insert_unit(id, next, slot, units, unit.get("yard", []), unit.get("yard_open", false))
	unit.position_raw = position_raw.duplicate()
	unit.flags |= 0x10000
