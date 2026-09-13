extends SceneTree
const Gate = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/upkeep.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual: Dictionary = JSON.parse_string(JSON.stringify(Gate.apply(item.upkeep, item.debt, item.requested, item.accepted)))
		if Gate.float32(actual.requested) != Gate.float32(item.expected.requested) or Gate.float32(actual.accepted) != Gate.float32(item.expected.accepted) or int(actual.productive) != int(item.expected.productive):
			differences.append({"input": item, "actual": actual})
	FileAccess.open("res://../analysis/native-upkeep-gate-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "mismatches": differences.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Nonnegative upkeep request/acceptance and productive gate with supplied debt; excludes settlement and update cadence"}, "  ") + "\n")
	print("UPKEEP_GATE %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
