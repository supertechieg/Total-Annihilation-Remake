extends SceneTree
const Deadline = preload("res://direct_deadline.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/direct-deadline.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Deadline.deadline(int(item.tick), int(item.speed), int(item.range), int(item.timer), item.no_auto)
		if actual != int(item.expected):
			differences.append({"input": item, "actual": actual})
	var report := {"cases": trace.cases.size(), "mismatches": differences.size(), "exe_sha256": trace.exe_sha256,
		"scope": "Original direct launcher deadline block 0x49cb1c..0x49cb61; unsigned range/speed division, timer override, zero speed and tick wrap; excludes surrounding launcher", "differences": differences}
	FileAccess.open("res://../analysis/native-direct-deadline-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("DIRECT_DEADLINE %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
