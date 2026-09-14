extends SceneTree
const VM = preload("res://cob_vm.gd")
const Catalog = preload("res://unit_catalog.gd")

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/killed/native-trace.json"))
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var mismatches: Array = []
	for case: Dictionary in trace.cases:
		var vm := VM.new(catalog.load_script(str(case.unit)))
		vm.read_values = {4: 100, 17: 100}
		vm.invoke("Create")
		var invocation: int = vm.invoke("Killed", [int(case.severity), 0])
		var completed: bool = vm.completions.has(invocation)
		var corpse := int(vm.completions[invocation].locals[1]) if completed else -999
		var hidden: Array = []
		for index in range(vm.pieces.size()):
			if not vm.pieces[index].visible:
				hidden.append(index)
		var explosions: Array = vm.explosions.map(func(item: Array) -> Array: return [int(item[0]), int(item[1])])
		var expected_explosions: Array = case.explosions.map(func(item: Array) -> Array: return [int(item[0]), int(item[1])])
		var expected_hidden: Array = case.hidden.map(func(item) -> int: return int(item))
		if not completed or corpse != int(case.corpsetype) or explosions != expected_explosions or hidden != expected_hidden or not vm.fault.is_empty():
			if mismatches.size() < 3:
				mismatches.append({"unit": case.unit, "severity": case.severity, "corpse": corpse, "expected": case.corpsetype,
					"explosions": explosions.slice(0, 3), "expected_explosions": expected_explosions.slice(0, 3), "fault": vm.fault})
			else:
				mismatches.append({})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatch_count": mismatches.size(), "mismatches": mismatches.slice(0, 3),
		"scope": "Original synchronous Killed(severity, corpsetype) through 0x4b0bc0 after Create for 32 level-one unit and structure scripts at 11 severities: returned corpse type, EXPLODE (vtable+0x34) piece/flag order and hidden pieces; excludes debris simulation, death explosion and corpse placement"}
	FileAccess.open("res://../analysis/native-killed-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true) + "\n")
	print("NATIVE_KILLED %d / %d cases match" % [trace.cases.size() - mismatches.size(), trace.cases.size()])
	quit(0 if mismatches.is_empty() else 1)
