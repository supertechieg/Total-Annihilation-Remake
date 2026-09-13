extends SceneTree
const Footprint = preload("res://footprint_passability.gd")
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/footprint-passability/native.json"))
	var differences: Array = []
	var cells := 0
	for value: Dictionary in source.cases:
		var actual := Footprint.prepare(PackedByteArray(value.allowed), int(value.width), int(value.height), Vector2i(int(value.footprint[0]), int(value.footprint[1])))
		for index in range(actual.size()):
			cells += 1
			if actual[index] != int(value.expected[index]):
				differences.append(cells)
	var file := FileAccess.open("res://../analysis/native-live-footprint-passability-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cells": cells, "differences": differences, "exe_sha256": source.exe_sha256,
		"scope": "Godot static Boolean-terrain footprint/clearance aggregation versus original 0x440500; excludes position lookup and dynamic occupancy"}, "  ") + "\n")
	print("LIVE_FOOTPRINT_PASSABILITY %d / %d match" % [cells - differences.size(), cells])
	quit(0 if differences.is_empty() else 1)
