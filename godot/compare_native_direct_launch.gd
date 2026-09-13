extends SceneTree
const Launch = preload("res://direct_launch.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/emg-launch.json"))
	var mismatches: Array = []
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var actual: Dictionary = JSON.parse_string(JSON.stringify(Launch.solve(case.source, case.target, int(case.speed))))
		if actual != case.expected:
			mismatches.append({"case": index, "actual": actual, "expected": case.expected})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches, "scope": "Original 0x49ca37..0x49cb1c direct launch with zero start velocity/acceleration; supplied coordinates and speeds; excludes creation and callbacks"}
	FileAccess.open("res://../analysis/native-direct-launch-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_DIRECT_LAUNCH %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
