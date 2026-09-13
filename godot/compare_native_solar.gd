extends SceneTree
const VM = preload("res://cob_vm.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("solar/native-trace.json")))
	var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/armsolar/script.json")))
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
			vm.invoke(item.action)
		var threads: Array = []
		for slot in range(vm.slots.size()):
			if vm.slots[slot] != null:
				threads.append({"slot": slot, "pc": vm.slots[slot].pc, "state": vm.slots[slot].state})
		var values: Dictionary = {}
		for key in vm.values:
			values[str(key)] = vm.values[key]
		var actual: Dictionary = JSON.parse_string(JSON.stringify({"statics": vm.statics, "pieces": vm.pieces, "threads": threads, "values": values}))
		if actual != item.state or not vm.fault.is_empty():
			failures += 1
			if differences.size() < 3:
				differences.append({"tick": item.tick, "action": item.action, "fault": vm.fault, "actual": actual, "expected": item.state})
	var report := {"snapshots": trace.snapshots.size(), "mismatches": failures, "exe_sha256": trace.exe_sha256,
		"scope": "Healthy solar script activation/deactivation with supplied host reads; excludes damaged smoke, destruction and world lifecycle", "differences": differences}
	FileAccess.open(folder.path_join("solar/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_SOLAR_COMPARISON %d / %d snapshots match" % [trace.snapshots.size() - failures, trace.snapshots.size()])
	quit(0 if failures == 0 else 1)
