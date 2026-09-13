extends SceneTree
const TargetPoint = preload("res://target_point.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/target-point/native.json"))
	var mismatches: Array = []
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var actual := TargetPoint.from_runtime_vertices(case.vertices, case.position)
		for axis in range(3):
			if int(actual[axis]) != int(case.expected[axis]):
				mismatches.append({"case": index, "actual": actual, "expected": case.expected})
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Complete original 0x43e0b0 with supplied runtime vertices and seven piece indices; excludes vertex transformation, SweetSpot callback and live combat integration"}
	FileAccess.open("res://../analysis/native-target-point-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_TARGET_POINT %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
