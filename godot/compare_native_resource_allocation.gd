extends SceneTree
const Allocation = preload("res://resource_allocation.gd")
const Float = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/allocation.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Allocation.allocate(item.available, item.debt, item.accepted)
		for key in actual:
			if Float.float32(actual[key]) != Float.float32(item.expected[key]):
				differences.append({"input": item, "actual": actual})
				break
	FileAccess.open("res://../analysis/native-resource-allocation-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "mismatches": differences.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Original aggregate allocation loop with finite nonnegative supplied totals; excludes aggregation, capacity clamp, individual debt update and cadence"}, "  ") + "\n")
	print("RESOURCE_ALLOCATION %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
