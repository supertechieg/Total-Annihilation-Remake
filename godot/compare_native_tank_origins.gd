extends SceneTree
const Origin = preload("res://piece_origin.gd")
const Catalog = preload("res://unit_catalog.gd")
const VM = preload("res://cob_vm.gd")
const Queries = preload("res://weapon_queries.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/piece-origin/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-tanks.json")))
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var name := str(case.get("name", ""))
		if case.get("aim_from", false):
			var vm := VM.new(catalog.load_script(case.unit))
			if case.get("fallback", false):
				vm.functions.erase("AimFromPrimary")
			for index in range(case.statics.size()):
				vm.statics[index] = int(case.statics[index])
			var queries := Queries.new(vm)
			name = queries.piece_name(true)
			if not queries.fault.is_empty():
				mismatches += 1
				continue
		var actual := Origin.model_origin(catalog.load_unit(case.unit).model, case.poses, name, case.angles)
		for axis in range(3):
			if int(actual[axis]) != int(case.expected[axis]):
				mismatches += 1
				break
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Flash/Raider/Stumpy/Hammer/Peewee/Rocko muzzle and AimFromPrimary queries with native firing poses and four headings; original axis conversion/setters/traversal; synthetic name ordering; excludes full loader and renderer"}
	FileAccess.open(folder.path_join("native-tank-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_TANK_ORIGIN_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
