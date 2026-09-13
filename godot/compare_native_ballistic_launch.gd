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
	for case: Dictionary in trace.offsets:
		if Launch.initial_offset(int(case.muzzle_z), int(case.aim_z)) != int(case.expected):
			mismatches += 1
	var total: int = trace.cases.size() + trace.offsets.size()
	var report := {"exe_sha256": trace.exe_sha256, "cases": total, "velocity_cases": trace.cases.size(), "offset_cases": trace.offsets.size(), "mismatches": mismatches,
		"scope": "Launch velocity block 0x49ce4f..0x49cecc and initial offset block 0x49e0fb..0x49e11e; original trig helpers and arithmetic with supplied controller/coordinate inputs; excludes native piece transforms, subsequent offset writes and lifetime"}
	FileAccess.open(folder.path_join("native-launch-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_BALLISTIC_LAUNCH_COMPARISON %d / %d cases match" % [total - mismatches, total])
	quit(0 if mismatches == 0 else 1)
