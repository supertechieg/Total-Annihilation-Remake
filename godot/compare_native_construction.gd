extends SceneTree
const Construction = preload("res://construction_math.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/construction/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-trace.json")))
	var failures := 0
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual: Dictionary = Construction.advance(item.input)
		var mismatch := false
		for key: String in actual:
			if key in ["accepted", "health"]:
				mismatch = mismatch or actual[key] != item.expected[key]
			else:
				# Compare original stored float32 bits, not JSON's decimal formatting.
				mismatch = mismatch or PackedFloat32Array([actual[key]]).to_byte_array() != PackedFloat32Array([item.expected[key]]).to_byte_array()
		if mismatch:
			failures += 1
			if differences.size() < 5:
				differences.append({"case": item, "actual": actual})
	var report := {"cases": trace.cases.size(), "mismatches": failures, "exe_sha256": trace.exe_sha256,
		"scope": "Positive construction work and request acceptance; excludes reclaim, resource settlement, and completion lifecycle", "differences": differences}
	FileAccess.open(folder.path_join("native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_CONSTRUCTION_COMPARISON %d / %d cases match" % [trace.cases.size() - failures, trace.cases.size()])
	quit(0 if failures == 0 else 1)
