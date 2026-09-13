extends SceneTree
const Heights = preload("res://terrain_heights.gd")
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/terrain-heights/native.json"))
	var differences: Array = []
	var cells := 0
	for value: Dictionary in source.cases:
		var actual := Heights.prepare(PackedByteArray(value.heights), int(value.width), int(value.height))
		for index in range(value.heights.size()):
			cells += 1
			if actual.low[index] != int(value.low[index]) or actual.high[index] != int(value.high[index]):
				differences.append({"cell": index, "map": cells})
	var file := FileAccess.open("res://../analysis/native-live-terrain-heights-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cells": cells, "differences": differences, "exe_sha256": source.exe_sha256,
		"scope": "Godot full-map cell extrema compared to original 0x483210 with supplied grids; excludes footprint aggregation, feature boundaries and pathfinding"}, "  ") + "\n")
	print("LIVE_TERRAIN_HEIGHTS %d / %d match" % [cells - differences.size(), cells])
	quit(0 if differences.is_empty() else 1)
