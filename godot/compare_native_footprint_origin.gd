extends SceneTree
const Origin = preload("res://footprint_origin.gd")
func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/metal-maker/footprint.json"))
	var differences: Array = []
	for item: Dictionary in trace.cases:
		var actual := [Origin.axis(int(item.position), int(item.width)), Origin.axis(int(item.position), int(item.height))]
		if actual[0] != int(item.expected[0]) or actual[1] != int(item.expected[1]):
			differences.append({"input": item, "actual": actual})
	FileAccess.open("res://../analysis/native-footprint-origin-validation.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": trace.cases.size(), "differences": differences, "exe_sha256": trace.exe_sha256, "scope": "Original position update footprint conversion; spatial remove/add and unit refresh callbacks stubbed"}, "  ") + "\n")
	print("FOOTPRINT_ORIGIN %d / %d match" % [trace.cases.size() - differences.size(), trace.cases.size()])
	quit(0 if differences.is_empty() else 1)
