extends SceneTree
const TargetPoint = preload("res://target_point.gd")
const Catalog = preload("res://unit_catalog.gd")
const VM = preload("res://cob_vm.gd")
const Queries = preload("res://weapon_queries.gd")

func _initialize() -> void:
	var roster := "--roster" in OS.get_cmdline_user_args()
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/target-point/roster.json" if roster else "res://../local/target-point/tanks.json"))
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var mismatches: Array = []
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var vm := VM.new(catalog.load_script(case.unit))
		for i in range(case.statics.size()):
			vm.statics[i] = int(case.statics[i])
		var query := Queries.new(vm)
		var piece := query.output("SweetSpot", 0)
		var model: Dictionary = catalog.load_unit(case.unit).model
		var names: Array = []
		for pose: Dictionary in vm.pieces:
			names.append(str(pose.name))
		for item: Dictionary in model.pieces:
			if str(item.name) not in names:
				names.append(str(item.name))
		if not query.fault.is_empty() or piece < 0 or piece >= names.size():
			mismatches.append({"case": index, "fault": query.fault})
			continue
		var actual := TargetPoint.model_point(model, case.poses, names[piece], case.angles, case.position)
		for axis in range(3):
			if int(actual[axis]) != int(case.expected[axis]):
				mismatches.append({"case": index, "actual": actual, "expected": case.expected})
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Flash/Raider/Stumpy original axis conversion, full dirty vertex update and SweetSpot wrapper with firing snapshots at four headings; synthetic name ordering; excludes cache timing"}
	if roster:
		report.scope = "All prepared unit models at zero script pose and four headings: original axis conversion, dirty update and SweetSpot wrapper; excludes Create, animated poses, cache timing and full model loader"
	FileAccess.open("res://../analysis/native-roster-target-validation.json" if roster else "res://../analysis/native-tank-target-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("NATIVE_TANK_TARGETS %d / %d match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
