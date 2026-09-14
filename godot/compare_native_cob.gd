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
	var args := OS.get_cmdline_user_args()
	var core := "--core" in args or "--corcom" in args
	var trace_name := "scripts/native-trace-corcom.json" if core else "scripts/native-trace.json"
	var script_name := "unit-assets/corcom/script.json" if core else "viewer-assets/armcom.cob.json"
	var report_name := "scripts/native-comparison-corcom.json" if core else "scripts/native-comparison.json"
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(trace_name)))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(script_name)))
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
	FileAccess.open(root.path_join(report_name), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	if core:
		# Aggregate summary for source review; excludes raw trace bytes and original bytecode.
		var analysis_path := ProjectSettings.globalize_path("res://../analysis/core-commander-native-validation.json")
		var scenario_summary: Dictionary = {}
		for key in oracle.scenario.keys():
			scenario_summary[str(key)] = oracle.scenario[key]
		var summary := {
			"unit": "corcom",
			"script": "local/unit-assets/corcom/script.json",
			"executable_sha256": oracle.exe_sha256,
			"cob_sha256": oracle.cob_sha256,
			"instruction_count": int(data.instructions.size()),
			"static_count": int(data.static_count),
			"piece_count": int(data.pieces.size()),
			"snapshots_checked": checked,
			"mismatches": failures,
			"vm_fault": vm.fault,
			"ticks_replayed": 451,
			"scenario_scope": "Create/StartMoving/StopMoving/AimPrimary/FirePrimary/AimTertiary/FireTertiary/StartBuilding/TargetCleared/StopBuilding (identical to armcom oracle scenario)",
			"scenario_calls": scenario_summary,
			"host_callbacks_exercised": ["set_transform(0)", "set_rotation(1)", "set_visible(2)", "get_transform(5)", "get_rotation(6)", "set_value(16)"],
			"scope_limits": "Original bytecode against reconstructed VM only; no world simulation, weapons, damage, or combat behavior is validated here. Report matches Core Commander lifecycle callbacks used by the viewer (movement, aim, build, target clear) with no VM fault.",
		}
		FileAccess.open(analysis_path, FileAccess.WRITE).store_string(JSON.stringify(summary, "  "))
	print("NATIVE_COMPARISON %d / %d snapshots match; VM fault: %s" % [checked - failures, checked, vm.fault])
	quit(0 if failures == 0 else 1)
