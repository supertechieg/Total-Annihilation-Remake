extends SceneTree
const Grid = preload("res://collision_grid.gd")

func _initialize() -> void:
	var grid = Grid.new(8, 8)
	var units := {1: {"flags": 1, "replaceable": false},
		2: {"flags": 0, "replaceable": false}, 3: {"flags": 0, "replaceable": true}}
	grid.cells[9] = [2, 0]
	grid.cells[10] = [3, 0]
	var rect := Rect2i(1, 1, 3, 1)
	var checks := [grid.insert_unit(1, rect, 0, units)]
	checks.append(grid.cells[9][0] == 2 and grid.cells[10][0] == 1 and grid.cells[11][0] == 1)
	checks.append(units[1].flags == 0xc000001 and units[2].flags == 0x4000000 and units[3].flags == 0x8000000)
	grid.remove_unit(1, rect, 0, units, true)
	checks.append(grid.cells[9][0] == 2 and grid.cells[10][0] == 0 and grid.cells[11][0] == 0)
	checks.append(units[1].flags == 1)
	checks.append(not grid.insert_unit(1, Rect2i(7, 1, 1, 1), 0, units))
	checks.append(grid.insert_unit(1, Rect2i(2, 2, 1, 1), 1, units))
	checks.append(grid.cells[18] == [0, 1])
	var failures := checks.count(false)
	print("COLLISION_GRID %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
