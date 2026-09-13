extends SceneTree
const Yield = preload("res://extractor_yield.gd")
const Float = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/extractor.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var metal := PackedByteArray()
		metal.resize(1024)
		for i in range(1024):
			metal[i] = ((i * 73 + 19) & 255) if int(item.pattern) == -1 else int(item.pattern)
		var actual := Yield.calculate(metal, 32, 32, Rect2i(int(item.x), int(item.z), int(item.width), int(item.height)), item.scale, item.previous)
		if Float.float32(actual) != Float.float32(item.expected):
			differences.append({"input": item, "actual": actual})
	FileAccess.open("res://../analysis/native-extractor-yield-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Original extractor setup and map lookup with supplied metal bytes; excludes map loading and SetSpeed script callback"}, "  ") + "\n")
	print("EXTRACTOR_YIELD %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
