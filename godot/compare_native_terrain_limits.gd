extends SceneTree
const Limits = preload("res://terrain_limits.gd")
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/terrain-limits/native.json"))
	var differences: Array = []
	for value: Dictionary in source.cases:
		var actual := Limits.passable(int(value.low), int(value.high), int(value.sea), int(value.maximum), int(value.minimum), int(value.slope), int(value.water_slope))
		if actual != value.expected:
			differences.append(value)
	var file := FileAccess.open("res://../analysis/native-terrain-limits-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": source.cases.size(), "differences": differences, "exe_sha256": source.exe_sha256,
		"scope": "Original cell terrain predicate with supplied ordered height bytes and clamped bad slopes; no features/occupants; excludes height-grid preparation and footprint aggregation"}, "  ") + "\n")
	print("TERRAIN_LIMITS %d / %d match" % [source.cases.size() - differences.size(), source.cases.size()])
	quit(0 if differences.is_empty() else 1)
