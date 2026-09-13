extends SceneTree
const VM = preload("res://cob_vm.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var unit := "corraid" if "--corraid" in OS.get_cmdline_user_args() else "armflash"
	if "--armstump" in OS.get_cmdline_user_args():
		unit = "armstump"
	if "--armham" in OS.get_cmdline_user_args():
		unit = "armham"
	if "--armpw" in OS.get_cmdline_user_args():
		unit = "armpw"
	if "--armrock" in OS.get_cmdline_user_args():
		unit = "armrock"
	var trace_folder := "firing/" + unit if unit != "armflash" else "firing"
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(trace_folder + "/native-trace.json")))
	var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/" + unit + "/script.json")))
	var vm = VM.new(program)
	vm.read_values = {4: 100, 17: 0}
	var differences: Array = []
	var failures := 0
	for item: Dictionary in trace.snapshots:
		var invocation := -1
		if item.action == "step":
			vm.step()
		else:
			invocation = vm.invoke(item.action, item.args)
		var threads: Array = []
		for slot in range(vm.slots.size()):
			if vm.slots[slot] != null:
				threads.append({"slot": slot, "pc": vm.slots[slot].pc, "state": vm.slots[slot].state})
		var actual: Dictionary = JSON.parse_string(JSON.stringify({"statics": vm.statics, "pieces": vm.pieces,
			"threads": threads, "values": vm.values, "spin_targets": vm.spin_targets,
			"spin_acceleration": vm.spin_acceleration, "shading": vm.shading, "caching": vm.caching}))
		var query_matches := true
		if item.has("query_piece"):
			query_matches = vm.completions.has(invocation) and int(vm.completions[invocation].locals[0]) == int(item.query_piece)
		if actual != item.state or not query_matches or not vm.fault.is_empty():
			failures += 1
			if differences.size() < 3:
				differences.append({"tick": item.tick, "action": item.action, "fault": vm.fault, "query_matches": query_matches, "actual": actual, "expected": item.state})
	var report := {"unit": unit, "snapshots": trace.snapshots.size(), "mismatches": failures, "exe_sha256": trace.exe_sha256,
		"scope": "Healthy ground-unit recoil, muzzle visibility, query locals, overlapping firing and optional HitByWeapon callbacks at supplied times; excludes original host cadence/projectiles", "queries": trace.queries, "differences": differences}
	FileAccess.open(folder.path_join(trace_folder + "/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_FIRING_COMPARISON %s: %d / %d snapshots match" % [unit, trace.snapshots.size() - failures, trace.snapshots.size()])
	quit(0 if failures == 0 else 1)
