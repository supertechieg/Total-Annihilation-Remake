extends SceneTree
const Origin = preload("res://piece_origin.gd")
const Catalog = preload("res://unit_catalog.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/piece-origin/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-tanks.json")))
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual := Origin.model_origin(catalog.load_unit(case.unit).model, case.poses, case.name, case.angles)
		for axis in range(3):
			if int(actual[axis]) != int(case.expected[axis]):
				mismatches += 1
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Flash/Raider native firing poses through original move/rotation setters and origin traversal; four headings; prepared model geometry, synthetic name ordering; excludes original loader execution and renderer"}
	FileAccess.open(folder.path_join("native-tank-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_TANK_ORIGIN_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
