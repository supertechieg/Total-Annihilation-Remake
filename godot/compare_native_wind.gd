extends SceneTree
const Wind = preload("res://wind_state.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/wind/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-wind.json")))
	var wind := Wind.new()
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual: Dictionary = wind.advance(case)
		var matches := PackedFloat32Array([actual.ratio])[0] == PackedFloat32Array([case.expected.ratio])[0]
		for key: String in ["next_tick", "strength", "heading", "changed", "crt_seed", "game_seed"]:
			matches = matches and int(actual[key]) == int(case.expected[key])
		for axis in range(3):
			matches = matches and int(actual.drift[axis]) == int(case.expected.drift[axis])
		if not matches:
			if mismatches < 2:
				print("WIND_DIFFERENCE ", {"input": case, "actual": actual})
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Wind timer gating, original CRT/game RNG state transitions, bounded strength/heading draws, drift and float32 normalized strength; synthetic CRT thread storage; excludes initial seeding and world scheduling"}
	FileAccess.open(folder.path_join("native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	FileAccess.open(folder.path_join("../../analysis/native-wind-state-validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_WIND_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
