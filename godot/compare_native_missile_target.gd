extends SceneTree
const Target = preload("res://missile_target.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/missile-target.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Target.select(item)
		if actual != item.expected:
			differences.append({"input": item, "actual": actual})
	var report := {"cases": trace.cases.size(), "mismatches": differences.size(), "exe_sha256": trace.exe_sha256,
		"scope": "Original full 0x49b3e0 non-cruise pointer selection: projectile priority, valid unit position and saved-point fallback; excludes cruise, target assignment and pointer cleanup", "differences": differences}
	FileAccess.open("res://../analysis/native-missile-target-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("MISSILE_TARGET %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
