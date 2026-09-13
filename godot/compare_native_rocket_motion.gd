extends SceneTree
const Motion = preload("res://rocket_motion.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/rocket-motion.json"))
	var mismatches: Array = []
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var actual: Dictionary = JSON.parse_string(JSON.stringify(Motion.advance(case)))
		if actual != case.expected:
			mismatches.append({"case": index, "actual": actual, "expected": case.expected})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original 0x49b720 unguided self-propelled update: acceleration, velocity and post-deadline gravity; collision/consolidation stubbed; no water, guidance, smoke, burnblow or cruise"}
	FileAccess.open("res://../analysis/native-rocket-motion-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_ROCKET_MOTION %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
