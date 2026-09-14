extends SceneTree
## Compares slot exhaustion (host start, START_SCRIPT and CALL_SCRIPT drops), RAND and EMIT_SFX
## against tools/native_cob_overflow.py, including per-slot stack pointers, stack words and wait slots.
const VM = preload("res://cob_vm.gd")
const GameRandom = preload("res://wind_state.gd")
const STATES := {"ready": 0x1000000, "turn": 0x2100000, "move": 0x2200000, "sleep": 0x2400000, "call": 0x2800000}

func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://../local/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("scripts/native-overflow-trace.json")))
	var vm = VM.new(trace.program)
	vm.rng = GameRandom.new()
	vm.rng.game_seed = int(trace.seed_start)
	var failures := 0
	var differences: Array = []
	for item: Dictionary in trace.snapshots:
		var started := true
		if item.action == "step":
			vm.step()
		else:
			started = vm.invoke(item.action, [], true) >= 0
		var slots: Array = []
		for i in range(VM.SLOT_COUNT):
			var thread = vm.slots[i]
			if thread == null:
				continue
			var entry := {"slot": i, "pc": thread.pc, "sp": thread.sp, "stack": thread.stack.slice(0, 4), "state": "0x%x" % STATES[thread.state]}
			if thread.state == "call":
				entry["wait_slot"] = thread.wait_slot
			slots.append(entry)
		var actual: Dictionary = JSON.parse_string(JSON.stringify({"started": started, "slots": slots, "statics": vm.statics}))
		var expected := {"started": item.started, "slots": item.slots, "statics": item.statics}
		if actual != expected or not vm.fault.is_empty():
			failures += 1
			if differences.size() < 4:
				differences.append({"tick": item.tick, "action": item.action, "fault": vm.fault, "actual": actual, "expected": expected})
	var sfx: Array = JSON.parse_string(JSON.stringify(vm.sfx_events))
	var trace_matches: bool = sfx == trace.sfx and vm.rng.game_seed == int(trace.seed_end) and vm.dropped_calls >= trace.dropped.size()
	var report := {"snapshots": trace.snapshots.size(), "mismatches": failures, "exe_sha256": trace.exe_sha256,
		"sfx": trace.sfx, "seed_end": trace.seed_end, "host_dropped_calls": vm.dropped_calls, "native_dropped_host_starts": trace.dropped.size(),
		"sfx_seed_match": trace_matches,
		"scope": "Synthetic script: eight busy slots, dropped host start, START_SCRIPT and CALL_SCRIPT with no free slot (arguments left on stack, wait slot -1), signal release, seeded RAND and EMIT_SFX; slot pc/sp/stack/state compared every tick",
		"differences": differences}
	FileAccess.open(root.path_join("scripts/native-overflow-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_COB_OVERFLOW_COMPARISON %d / %d snapshots match; sfx/seed %s; host drops %d" % [trace.snapshots.size() - failures, trace.snapshots.size(), "match" if trace_matches else "MISMATCH", vm.dropped_calls])
	quit(0 if failures == 0 and trace_matches else 1)
