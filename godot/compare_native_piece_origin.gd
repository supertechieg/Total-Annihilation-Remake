extends SceneTree
const Origin = preload("res://piece_origin.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/piece-origin/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-origins.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual := Origin.origin(case.pieces, int(case.target), case.angles)
		for axis in range(3):
			if int(actual[axis]) != int(case.expected[axis]):
				if mismatches < 2:
					print("ORIGIN_DIFFERENCE ", {"actual": actual, "case": case})
				mismatches += 1
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original piece-origin traversal with supplied offsets, moves, parent rotations and unit angles; synthetic hierarchies; excludes COB-to-model pose binding and renderer"}
	FileAccess.open(folder.path_join("native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_PIECE_ORIGIN_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
