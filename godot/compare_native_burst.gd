extends SceneTree
const Burst = preload("res://burst_schedule.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/burst/native.json"))
	var mismatches: Array = []
	var transitions := 0
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var source := {"position": case.position, "timestamp": int(case.timestamp), "deadline": 0, "remaining": int(case.remaining), "removed": false}
		var result := Burst.advance(source, int(case.tick), int(case.interval), int(case.timer), int(case.speed), int(case.distance), case.fresh)
		# JSON normalization makes native integer arrays comparable to GDScript arrays.
		var actual: Dictionary = JSON.parse_string(JSON.stringify(result))
		if actual.source != case.source or actual.copy != case.copy or bool(actual.refresh) != (case.queries.size() == 1):
			mismatches.append({"case": index, "actual": actual, "expected_source": case.source, "expected_copy": case.copy})
		transitions += 1
		for step: Dictionary in case.get("steps", []):
			result = Burst.advance(result.source, int(step.tick), int(case.interval), int(case.timer), int(case.speed), int(case.distance), step.fresh)
			actual = JSON.parse_string(JSON.stringify(result))
			transitions += 1
			if actual.source != step.source or actual.copy != step.copy or bool(actual.refresh) != (step.queries.size() == 1):
				mismatches.append({"case": index, "tick": step.tick, "actual": actual, "expected_source": step.source, "expected_copy": step.copy})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "transitions": transitions, "mismatches": mismatches,
		"scope": "Original 0x49b720 with one burst source: due check, odd/even position refresh, copied state, expiry and removal; controlled muzzle callback, disabled pool consolidation, no sounds/random spread/capacity exhaustion"}
	FileAccess.open("res://../analysis/native-burst-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_BURST %d / %d transitions match" % [transitions - mismatches.size(), transitions])
	quit(0 if mismatches.is_empty() else 1)
