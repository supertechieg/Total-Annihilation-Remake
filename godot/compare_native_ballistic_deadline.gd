extends SceneTree
const Launch = preload("res://ballistic_launch.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/ballistics/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-deadline.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		if Launch.deadline(int(case.tick), int(case.timer), case.burnblow, case.start, case.target, int(case.speed)) != int(case.expected):
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Cannon launch deadline; positive horizontal speed, ordinary coordinate differences; excludes zero divisor and extreme distance overflow"}
	FileAccess.open(folder.path_join("native-deadline-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("BALLISTIC_DEADLINE %d / %d native cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
