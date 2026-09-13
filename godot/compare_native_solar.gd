extends SceneTree
const VM = preload("res://cob_vm.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var metal_maker := "--armmakr" in OS.get_cmdline_user_args()
	var extractor := "--armmex" in OS.get_cmdline_user_args()
	var trace_folder := "metal-maker" if metal_maker else "solar"
	var unit := "armmakr" if metal_maker else "armsolar"
	if extractor:
		trace_folder = "extractor"
		unit = "armmex"
	var renewable := false
	for candidate: String in ["armwin", "armtide"]:
		if ("--" + candidate) in OS.get_cmdline_user_args():
			unit = candidate
			trace_folder = "wind-generator" if candidate == "armwin" else "tidal-generator"
			renewable = true
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(trace_folder + "/native-trace.json")))
	var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/" + unit + "/script.json")))
	var vm = VM.new(program)
	vm.read_values = {4: 100, 17: 100}
	vm.writable_values.assign([1, 5, 20])
	var failures := 0
	var differences: Array = []
	for item: Dictionary in trace.snapshots:
		if int(item.tick) >= 30:
			vm.read_values[17] = 0
		if item.action == "step":
			vm.step()
		else:
			vm.invoke(item.action, item.get("args", []))
		var threads: Array = []
		for slot in range(vm.slots.size()):
			if vm.slots[slot] != null:
				threads.append({"slot": slot, "pc": vm.slots[slot].pc, "state": vm.slots[slot].state})
		var values: Dictionary = {}
		for key in vm.values:
			values[str(key)] = vm.values[key]
		var actual: Dictionary = JSON.parse_string(JSON.stringify({"statics": vm.statics, "pieces": vm.pieces, "threads": threads, "values": values}))
		if metal_maker or extractor or renewable:
			actual.merge(JSON.parse_string(JSON.stringify({"shading": vm.shading, "caching": vm.caching, "spin_targets": vm.spin_targets, "spin_acceleration": vm.spin_acceleration})))
		if actual != item.state or not vm.fault.is_empty():
			failures += 1
			if differences.size() < 3:
				differences.append({"tick": item.tick, "action": item.action, "fault": vm.fault, "actual": actual, "expected": item.state})
	var report := {"snapshots": trace.snapshots.size(), "mismatches": failures, "exe_sha256": trace.exe_sha256,
		"scope": "Healthy resource-building script activation/deactivation and supplied speed/direction/host reads; excludes damaged smoke, destruction and world lifecycle", "differences": differences}
	if extractor:
		FileAccess.open(folder.path_join("../analysis/native-extractor-script-validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	if renewable:
		FileAccess.open(folder.path_join("../analysis/native-" + unit + "-script-validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	FileAccess.open(folder.path_join(trace_folder + "/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_SOLAR_COMPARISON %d / %d snapshots match" % [trace.snapshots.size() - failures, trace.snapshots.size()])
	quit(0 if failures == 0 else 1)
