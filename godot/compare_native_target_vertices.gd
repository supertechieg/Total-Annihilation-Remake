extends SceneTree
const TargetPoint = preload("res://target_point.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/target-point/vertices.json"))
	var mismatches: Array = []
	var count := 0
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		for number in range(case.pieces.size()):
			var piece: Dictionary = case.pieces[number]
			for v in range(piece.vertices.size()):
				count += 1
				var actual := TargetPoint.transform_vertex(case.pieces, number, piece.vertices[v], case.angles)
				for axis in range(3):
					if int(actual[axis]) != int(piece.expected[v][axis]):
						mismatches.append({"case": index, "piece": number, "vertex": v, "actual": actual, "expected": piece.expected[v]})
						break
	var report := {"exe_sha256": trace.exe_sha256, "trees": trace.cases.size(), "vertices": count, "mismatches": mismatches,
		"scope": "Complete 0x45ab10 dirty model update on synthetic pose trees; excludes model loading, cached updates and live SweetSpot integration"}
	FileAccess.open("res://../analysis/native-target-vertices-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_TARGET_VERTICES %d / %d match" % [count - mismatches.size(), count])
	quit(0 if mismatches.is_empty() else 1)
