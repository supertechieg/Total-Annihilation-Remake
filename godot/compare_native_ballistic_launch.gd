extends SceneTree
const Launch = preload("res://ballistic_launch.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/ballistics/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-launch.json")))
	var launch := Launch.new()
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual := launch.velocity(int(case.heading), int(case.pitch), int(case.speed), int(case.gravity), int(case.travel))
		for axis in range(3):
			if actual[axis] != int(case.expected[axis]):
				mismatches += 1
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Launch velocity block 0x49ce4f..0x49cecc using original trig helpers, supplied heading/pitch, positive speed, gravity and unsigned travel accumulator; excludes accumulator evolution and lifetime"}
	FileAccess.open(folder.path_join("native-launch-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_BALLISTIC_LAUNCH_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
