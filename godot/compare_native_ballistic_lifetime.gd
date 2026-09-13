extends SceneTree
const Motion = preload("res://ballistic_motion.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/ballistics/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-lifetime.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var event := Motion.expiration(int(case.tick), int(case.deadline), int(case.timer), case.burnblow)
		var actual: Dictionary = Motion.integrate(case.position, case.velocity, 4369, [0, 0, 0]) if event == 0 else {"position": case.position, "velocity": case.velocity}
		var matches := event == int(case.event)
		for axis in range(3):
			matches = matches and int(actual.position[axis]) == int(case.expected_position[axis]) and int(actual.velocity[axis]) == int(case.expected_velocity[axis])
		if not matches:
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Ballistic weapon timer/burnblow expiry decision and suppression of movement; impact/visual notifications stubbed, deadline initialization excluded"}
	FileAccess.open(folder.path_join("native-lifetime-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("BALLISTIC_LIFETIME %d / %d native cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
