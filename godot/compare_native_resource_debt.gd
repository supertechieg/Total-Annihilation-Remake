extends SceneTree
const Allocation = preload("res://resource_allocation.gd")
const Float = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/debt.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Allocation.settle(item.income, item.requested, item.accepted, item.debt, item.debt_fraction, item.accepted_fraction)
		for key in actual:
			if Float.float32(actual[key]) != Float.float32(item.expected[key]):
				differences.append({"input": item, "actual": actual})
				break
	FileAccess.open("res://../analysis/native-resource-debt-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "mismatches": differences.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Per-unit energy and metal debt settlement and accumulator rollover with supplied payment fractions; excludes aggregation and cadence"}, "  ") + "\n")
	print("RESOURCE_DEBT %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
