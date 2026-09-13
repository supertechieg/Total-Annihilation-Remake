extends SceneTree
const Reload = preload("res://weapon_reload.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/weapon-reload/native.json"))
	var mismatches: Array = []
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var actual := Reload.ticks(int(case.base), int(case.health), int(case.maximum), int(case.experience))
		if actual != int(case.expected):
			mismatches.append({"case": index, "actual": actual, "expected": case.expected})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original normal-weapon reload arithmetic, nonnegative signed-short health <= maximum; excludes countdown ordering, stockpiled weapons and experience accrual"}
	FileAccess.open("res://../analysis/native-weapon-reload-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_WEAPON_RELOAD %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
