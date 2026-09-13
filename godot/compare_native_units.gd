extends SceneTree
const VM = preload("res://cob_vm.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("mobile-scripts/index.json")))
	var failures := 0
	var total := 0
	var differences: Array = []
	for unit: String in index.units:
		var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("mobile-scripts/%s.json" % unit)))
		var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/%s/script.json" % unit)))
		var vm = VM.new(program)
		vm.read_values = {4: 100, 17: 100}
		for item: Dictionary in trace.snapshots:
			if int(item.tick) >= 30:
				vm.read_values[17] = 0
			if item.action == "step":
				vm.step()
			else:
				vm.invoke(item.action, item.args)
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
	var report := {"snapshots": total, "mismatches": failures, "units": index.units, "exe_sha256": index.exe_sha256,
		"scope": "Healthy Create, movement, supplied aiming, and builder callbacks when present; excludes firing, damage, destruction and full host timing", "differences": differences}
	FileAccess.open(folder.path_join("mobile-scripts/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_MOBILE_COMPARISON %d / %d snapshots match" % [total - failures, total])
	quit(0 if failures == 0 else 1)
