extends SceneTree
## Replays the same inputs as the isolated original interpreter and compares every snapshot.
const VM = preload("res://cob_vm.gd")
var failures := 0
var checked := 0
var differences: Array = []

func _initialize() -> void:
	call_deferred("run")

func comparable(vm) -> Dictionary:
	var threads: Array = []
	for i in range(vm.slots.size()):
		if vm.slots[i] != null:
			var thread: Dictionary = vm.slots[i]
			threads.append({"slot": i, "pc": thread.pc, "state": thread.state})
	var values: Dictionary = {}
	for key in vm.values:
		values[str(key)] = vm.values[key]
	return {"statics": vm.statics, "pieces": vm.pieces, "values": values, "threads": threads}

func compare(vm, reference: Dictionary) -> void:
	checked += 1
	# JSON input represents numbers as floats; normalize both sides before deep equality.
	var actual: Dictionary = JSON.parse_string(JSON.stringify(comparable(vm)))
	var expected: Dictionary = reference.state
	var mismatch := false
	for key: String in ["statics", "pieces", "values", "threads"]:
		if actual[key] != expected[key]:
			mismatch = true
			if differences.size() < 10:
				differences.append({"label": reference.label, "field": key, "expected": expected[key], "actual": actual[key].duplicate(true)})
	if not vm.fault.is_empty():
		mismatch = true
	if mismatch:
		failures += 1

func run() -> void:
	var root := ProjectSettings.globalize_path("res://../local/")
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("scripts/native-trace.json")))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("viewer-assets/armcom.cob.json")))
	var vm = VM.new(data)
	var cursor := 0
	for tick in range(451):
		if tick > 0:
			vm.step()
			compare(vm, oracle.snapshots[cursor])
			cursor += 1
		for call: Array in oracle.scenario.get(str(tick), []):
			vm.invoke(call[0], call[1])
			compare(vm, oracle.snapshots[cursor])
			cursor += 1
	var report := {"snapshots": checked, "mismatches": failures, "fault": vm.fault,
		"exe_sha256": oracle.exe_sha256, "cob_sha256": oracle.cob_sha256, "first_differences": differences}
	FileAccess.open(root.path_join("scripts/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_COMPARISON %d / %d snapshots match; VM fault: %s" % [checked - failures, checked, vm.fault])
	quit(0 if failures == 0 else 1)
