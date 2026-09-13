extends SceneTree
const Aim = preload("res://ballistic_aim.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/ballistics/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-aim.json")))
	var differences: Array = []
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual := Aim.solve(case.delta, int(case.speed), int(case.gravity), float(case.minimum))
		if actual != int(case.expected):
			mismatches += 1
			if differences.size() < 5:
				differences.append({"case": case, "actual": actual})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches, "differences": differences,
		"scope": "Ballistic launch-angle decisions with supplied source-minus-target coordinates, positive speed/gravity and minimum angle; excludes world targeting and projectile launch"}
	FileAccess.open(folder.path_join("native-aim-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_BALLISTIC_AIM_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	if mismatches > 0:
		print(differences)
	quit(0 if mismatches == 0 else 1)
