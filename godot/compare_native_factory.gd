extends SceneTree
const VM = preload("res://cob_vm.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var failures := 0
	var total := 0
	var differences: Array = []
	var executable_hash := ""
	for unit: String in ["armvp", "armlab", "corvp", "corlab", "spin0", "spin1", "spin2", "spin3", "spin4", "spin5"]:
		var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("factory/%s-trace.json" % unit)))
		if trace.has("exe_sha256"):
			executable_hash = trace.exe_sha256
		var program: Dictionary = trace.program if trace.has("program") else JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/%s/script.json" % unit)))
		var vm = VM.new(program)
		vm.read_values = {4: 100, 17: 100}
		vm.writable_values.assign([5, 18, 19])
		vm.readback_values.assign([18])
		for item: Dictionary in trace.snapshots:
			if int(item.tick) >= 30:
				vm.read_values[17] = 0
			if item.action == "step":
				vm.step()
			else:
				vm.invoke(item.action)
			var threads: Array = []
			for slot in range(vm.slots.size()):
				if vm.slots[slot] != null:
					threads.append({"slot": slot, "pc": vm.slots[slot].pc, "state": vm.slots[slot].state})
			var actual: Dictionary = JSON.parse_string(JSON.stringify({"statics": vm.statics, "pieces": vm.pieces,
				"threads": threads, "values": vm.values, "spin_targets": vm.spin_targets,
				"spin_acceleration": vm.spin_acceleration, "shading": vm.shading, "caching": vm.caching}))
			total += 1
			if actual != item.state or not vm.fault.is_empty():
				failures += 1
				if differences.size() < 3:
					differences.append({"unit": unit, "tick": item.tick, "action": item.action, "fault": vm.fault, "actual": actual, "expected": item.state})
	var report := {"snapshots": total, "mismatches": failures, "exe_sha256": executable_hash,
		"scope": "Original Arm and Core vehicle plant and Kbot lab healthy script playback with immediate clear-yard acknowledgements, plus six synthetic spin cases; not world production timing, combat or Core aircraft/naval/advanced factory", "differences": differences}
	FileAccess.open(folder.path_join("factory/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_FACTORY_COMPARISON %d / %d snapshots match" % [total - failures, total])
	quit(0 if failures == 0 else 1)
