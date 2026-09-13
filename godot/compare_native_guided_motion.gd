extends SceneTree
const Motion = preload("res://guided_motion.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/guided-motion.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual: Dictionary = JSON.parse_string(JSON.stringify(Motion.advance(item)))
		if actual != item.expected:
			differences.append({"input": item, "actual": actual})
	var report := {"cases": trace.cases.size(), "mismatches": differences.size(), "exe_sha256": trace.exe_sha256,
		"scope": "Full original update with ordinary guidance toward saved points; collision/consolidation stubbed; excludes burnblow, cruise, water and target references", "differences": differences}
	FileAccess.open("res://../analysis/native-guided-motion-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("GUIDED_MOTION %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
