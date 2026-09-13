extends SceneTree
const Renewable = preload("res://renewable_energy.gd")
const Float = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/renewable.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := Renewable.accumulate(item.income, item.active, item.extracts, int(item.makes), item.wind, item.tidal, item.strength, item.strength)
		if Float.float32(actual) != Float.float32(item.expected):
			differences.append({"input": item, "actual": actual})
	FileAccess.open("res://../analysis/native-renewable-energy-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Full settlement renewable energy contribution with supplied environment; excludes wind evolution, map environment loading, AI handicap and scripts"}, "  ") + "\n")
	print("RENEWABLE_ENERGY %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
