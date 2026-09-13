extends SceneTree
const Collision = preload("res://projectile_collision.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/collision/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-projectile.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var cell := Collision.cell_index(case.position, 4, 4)
		var target := Collision.unit_target(int(case.position[1]), int(case.owner), case.occupants) if cell >= 0 else 0
		if cell != int(case.cell) or target != int(case.target) or (cell < 0) != bool(case.expired):
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original endpoint grid lookup and two unit slots including ownership and height boundaries; excludes grid population, terrain, features and projectile proximity"}
	FileAccess.open(folder.path_join("native-projectile-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("PROJECTILE_COLLISION %d / %d native cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
