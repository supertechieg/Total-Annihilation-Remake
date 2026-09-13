extends SceneTree
const Steering = preload("res://missile_steering.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/missile-steering.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Steering.steer(item)
		if int(actual.heading) != int(item.expected.heading) or int(actual.pitch) != int(item.expected.pitch) or int(actual.accepted) != int(item.expected.accepted):
			differences.append({"input": item, "actual": actual})
	var report := {"cases": trace.cases.size(), "mismatches": differences.size(), "exe_sha256": trace.exe_sha256,
		"scope": "Original 0x49b520 steering toward supplied points, including turn bounds and rejection flag; excludes acquisition, target leading, flight and host flag mapping", "differences": differences}
	FileAccess.open("res://../analysis/native-missile-steering-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("MISSILE_STEERING %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
