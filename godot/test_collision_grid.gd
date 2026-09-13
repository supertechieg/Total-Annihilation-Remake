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
	var yard := [0x35, 0x2f, 0x31, 0]
	var yard_rect := Rect2i(1, 3, 4, 1)
	checks.append(grid.insert_unit(1, yard_rect, 1, units, yard, false))
	checks.append(grid.cells[25][0] == 1 and grid.cells[26][0] == 1 and grid.cells[27][0] == 0)
	checks.append(grid.terrain_flags[25] == 2 and grid.terrain_flags[27] == 2 and grid.terrain_flags[28] == 0)
	grid.remove_unit(1, yard_rect, 1, units, true, yard)
	checks.append(grid.terrain_flags[25] == 0 and grid.cells[26][0] == 0)
	checks.append(grid.insert_unit(1, yard_rect, 1, units, yard, true))
	checks.append(grid.cells[25][0] == 0 and grid.cells[26][0] == 1 and grid.cells[27][0] == 0)
	checks.append(grid.terrain_flags[25] == 2 and grid.terrain_flags[27] == 2)
	grid.remove_unit(1, yard_rect, 1, units, true, yard)
	checks.append(grid.cells[26][0] == 0 and grid.terrain_flags[27] == 0)
	checks.append(Grid.unit_rect([524287, 524288], Vector2i(2, 2)) == Rect2i(-1, 0, 2, 2))
	checks.append(Grid.unit_rect([524288, 524288], Vector2i(2, 2)) == Rect2i(0, 0, 2, 2))
	checks.append(Grid.unit_rect([1572863, 1572864], Vector2i(2, 2)) == Rect2i(0, 1, 2, 2))
	checks.append(Grid.unit_rect([0, 0], Vector2i(1, 1)) == Rect2i(0, 0, 1, 1))
	var moving_grid = Grid.new(8, 8)
	var moving_units := {1: {"flags": 1, "replaceable": false, "rect": Rect2i(1, 1, 1, 1), "slot": 0, "inserted": true}}
	moving_grid.insert_unit(1, moving_units[1].rect, 0, moving_units)
	moving_grid.move_unit(1, [1048577, 123, 1048577], 0, moving_units)
	checks.append(moving_grid.cells[9][0] == 1 and moving_units[1].flags == 0x10001)
	moving_grid.move_unit(1, [2097152, 456, 1048576], 1, moving_units)
	checks.append(moving_grid.cells[9][0] == 0 and moving_grid.cells[10][1] == 1)
	checks.append(moving_units[1].rect == Rect2i(2, 1, 1, 1) and moving_units[1].flags == 0x10002)
	moving_grid.move_unit(1, [-1, 0, 0], 1, moving_units)
	checks.append(not moving_units[1].inserted and moving_grid.cells[10][1] == 0)
	var failures := checks.count(false)
	print("COLLISION_GRID %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
