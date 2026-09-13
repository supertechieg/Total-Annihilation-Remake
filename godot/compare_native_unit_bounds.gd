extends SceneTree
const Bounds = preload("res://unit_bounds.gd")
const Catalog = preload("res://unit_catalog.gd")

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var folder := ProjectSettings.globalize_path("res://../local/splash/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-unit-bounds.json")))
	var mismatches: Array = []
	for case: Dictionary in trace.cases:
		var actual := Bounds.from_unit(catalog.load_unit(case.unit))
		for axis in range(3):
			if int(actual.lower[axis]) != int(case.lower[axis]) or int(actual.upper[axis]) != int(case.upper[axis]):
				mismatches.append(case.unit)
				break
	var report := {"exe_sha256": trace.exe_sha256, "units": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original recursive height on relocated original models and footprint bound arithmetic; excludes collision intersection and world placement"}
	FileAccess.open(folder.path_join("native-unit-bounds-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_UNIT_BOUNDS %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
