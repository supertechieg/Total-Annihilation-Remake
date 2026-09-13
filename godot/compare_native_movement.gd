extends SceneTree
const Motion = preload("res://ground_motion.gd")

func _initialize() -> void:
	var path := ProjectSettings.globalize_path("res://../local/movement/")
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("native-trace.json")))
	var motion = Motion.new()
	var differences: Array = []
	var failed := 0
	var count := 0
	for index in range(512):
		count += 1
		if motion.sine[index] != int(oracle.sine[index]):
			failed += 1
			differences.append({"sine_index": index})
	for item: Dictionary in oracle.cases:
		var actual: Dictionary = motion.advance_speed(item.input) if item.kind == "speed" else Motion.animation_transition(item.input)
		actual = JSON.parse_string(JSON.stringify(actual))
		count += 1
		if actual != item.expected:
			failed += 1
			if differences.size() < 10:
				differences.append({"case": item, "actual": actual})
	var report := {"checks": count, "mismatches": failed, "exe_sha256": oracle.exe_sha256,
		"scope": "Speed/vector primitive and animation callback transitions; excludes navigation, terrain sampling and collision",
		"first_differences": differences}
	FileAccess.open(path.path_join("native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_MOVEMENT_COMPARISON %d / %d checks match" % [count - failed, count])
	quit(0 if failed == 0 else 1)
