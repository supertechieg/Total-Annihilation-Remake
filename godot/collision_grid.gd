extends RefCounted
## Ordinary unit slots only; yard maps and overlap callbacks remain separate.
var width: int
var depth: int
var cells: Array = []

func _init(map_width: int, map_depth: int) -> void:
	width = map_width
	depth = map_depth
	for index in range(width * depth):
		cells.append([0, 0])

func insert_unit(id: int, rect: Rect2i, slot: int, units: Dictionary) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x >= width or rect.end.y >= depth:
		return false
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
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

func remove_unit(id: int, rect: Rect2i, slot: int, units: Dictionary, was_inserted: bool) -> void:
	if was_inserted:
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if int(cells[z * width + x][slot]) == id:
					cells[z * width + x][slot] = 0
	units[id].flags &= ~0xc000000
