extends SceneTree
const Grid = preload("res://collision_grid.gd")

func snapshot(grid: RefCounted, units: Dictionary) -> Dictionary:
	return {"cells": grid.cells.duplicate(true), "flags": [units[1].flags, units[2].flags, units[3].flags], "terrain_flags": grid.terrain_flags.duplicate()}

func same(actual: Dictionary, expected: Dictionary) -> bool:
	for id in range(3):
		if int(actual.flags[id]) != int(expected.flags[id]):
			return false
	for cell in range(64):
		if int(actual.terrain_flags[cell]) != int(expected.terrain_flags[cell]):
			return false
		for slot in range(2):
			if int(actual.cells[cell][slot]) != int(expected.cells[cell][slot]):
				return false
	return true

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/collision/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-grid.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var grid = Grid.new(8, 8)
		grid.cells = case.cells.duplicate(true)
		for cell in range(64):
			grid.terrain_flags[cell] = int(case.terrain_flags[cell])
		var units := {}
		for id in range(1, 4):
			units[id] = {"flags": int(case.initial_flags) if id == 1 else 0, "replaceable": case.replacement[id - 1]}
		var rect := Rect2i(int(case.x), int(case.z), int(case.width), int(case.depth))
		var inserted: bool = grid.insert_unit(1, rect, int(case.slot), units, case.yard, case.yard_open)
		var actual := snapshot(grid, units)
		units[1].merge({"rect": rect, "slot": int(case.slot), "inserted": inserted, "yard": case.yard, "yard_open": case.yard_open})
		grid.move_unit(1, case.position, int(case.next_slot), units)
		var moved := snapshot(grid, units)
		var position_matches := true
		for axis in range(3):
			position_matches = position_matches and (int(units[1].position_raw[axis]) & 0xffffffff) == int(case.moved.position[axis])
		for axis in range(2):
			position_matches = position_matches and (units[1].rect.position[axis] & 65535) == int(case.moved.origin[axis])
		grid.remove_unit(1, units[1].rect, int(case.next_slot), units, units[1].inserted, case.yard)
		var removed := snapshot(grid, units)
		if not same(actual, case.inserted) or not same(moved, case.moved) or not same(removed, case.removed) or not position_matches:
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Ordinary and yard-map insert/move/remove cells, position, terrain and overlap flags; excludes coarse lists, overlap callbacks and visibility"}
	FileAccess.open(folder.path_join("native-grid-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("COLLISION_GRID %d / %d native cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
