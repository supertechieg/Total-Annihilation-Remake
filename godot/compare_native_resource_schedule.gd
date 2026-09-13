extends SceneTree
const Schedule = preload("res://resource_schedule.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/schedule.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Schedule.poll(int(item.tick), int(item.deadline))
		if actual.due != item.expected.due or actual.deadline != int(item.expected.deadline):
			differences.append({"input": item, "actual": actual})
	FileAccess.open("res://../analysis/native-resource-schedule-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "mismatches": differences.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Unsigned economy deadline gate and 30-tick advance; excludes initial deadline and player/session eligibility"}, "  ") + "\n")
	print("RESOURCE_SCHEDULE %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
