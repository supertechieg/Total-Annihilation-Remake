extends SceneTree
const Grid = preload("res://collision_grid.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/collision/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-rect.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var rect := Grid.unit_rect(case.position, Vector2i(int(case.footprint[0]), int(case.footprint[1])))
		if rect.position.x != int(case.expected[0]) or rect.position.y != int(case.expected[1]):
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Creation position-to-cell arithmetic, footprints1..8 and signed32 coordinates including cell boundaries; excludes movement scheduling"}
	FileAccess.open(folder.path_join("native-rect-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("COLLISION_RECT %d / %d native cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
