extends SceneTree
const Motion = preload("res://beam_motion.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/beam-motion.json"))
	var mismatches: Array = []
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var actual: Dictionary = JSON.parse_string(JSON.stringify(Motion.advance(case)))
		if actual != case.expected:
			mismatches.append({"case": index, "actual": actual, "expected": case.expected})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches.slice(0, 3), "mismatch_count": mismatches.size(),
		"scope": "Original 0x49b720 line-of-sight update with and without beam flag 0x8: expiration, head movement, strict launch+duration tail release and released tail movement; collision/consolidation stubbed"}
	FileAccess.open("res://../analysis/native-beam-motion-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_BEAM_MOTION %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
