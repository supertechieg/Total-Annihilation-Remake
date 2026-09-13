extends SceneTree
const Motion = preload("res://ballistic_motion.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/ballistics/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-integration.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual := Motion.integrate(case.position, case.velocity, int(case.gravity), case.drift)
		for axis in range(3):
			if int(actual.position[axis]) != int(case.expected.position[axis]) or int(actual.velocity[axis]) != int(case.expected.velocity[axis]):
				mismatches += 1
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Live ballistic branch: position plus current velocity and supplied drift, then gravity; zero and unexpired nonzero flight timers; signed overflow; excludes aiming, drift derivation, gravity loading, expiration and collision"}
	FileAccess.open(folder.path_join("native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_BALLISTIC_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
