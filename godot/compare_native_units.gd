extends SceneTree
const VM = preload("res://cob_vm.gd")
const GameRandom = preload("res://wind_state.gd")

## Health read schedule (GET_VALUE 4) for a trace's scenario; healthy traces stay at 100.
static func health_at(schedule: Dictionary, tick: int) -> int:
	var value := 100
	var best := -1
	for key in schedule:
		if int(key) <= tick and int(key) > best:
			best = int(key)
			value = int(schedule[key])
	return value

func _initialize() -> void:
	var damaged := "--damaged" in OS.get_cmdline_user_args()
	var folder := ProjectSettings.globalize_path("res://../local/")
	var trace_folder := "mobile-scripts/damaged" if damaged else "mobile-scripts"
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(trace_folder + "/index.json")))
	var schedule: Dictionary = index.get("scenario", {}).get("health", {})
	var failures := 0
	var total := 0
	var sfx_total := 0
	var trace_failures := 0
	var differences: Array = []
	for unit: String in index.units:
		var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(trace_folder + "/%s.json" % unit)))
		var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/%s/script.json" % unit)))
		var vm = VM.new(program)
		vm.rng = GameRandom.new()
		vm.rng.game_seed = int(trace.get("seed_start", 0))
		vm.read_values = {4: 100, 17: 100}
		for item: Dictionary in trace.snapshots:
			if int(item.tick) >= 30:
				vm.read_values[17] = 0
			vm.read_values[4] = health_at(schedule, int(item.tick))
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
		# Whole-run EMIT_SFX list and final shared RNG seed.
		if trace.has("sfx"):
			var sfx: Array = JSON.parse_string(JSON.stringify(vm.sfx_events))
			sfx_total += trace.sfx.size()
			if sfx != trace.sfx or vm.sfx_count != trace.sfx.size() or vm.rng.game_seed != int(trace.seed_end) or vm.dropped_calls != trace.get("dropped", []).size():
				trace_failures += 1
				if differences.size() < 6:
					differences.append({"unit": unit, "sfx_actual": sfx.slice(0, 8), "sfx_expected": trace.sfx.slice(0, 8), "sfx_count": [vm.sfx_count, trace.sfx.size()],
						"seed": [vm.rng.game_seed, trace.seed_end], "dropped": [vm.dropped_calls, trace.get("dropped", []).size()]})
	var report := {"snapshots": total, "mismatches": failures, "units": index.units, "exe_sha256": index.exe_sha256,
		"sfx_events": sfx_total, "sfx_seed_mismatches": trace_failures,
		"scope": ("Damaged-seeded 600-tick lifecycle (health read 100/50/20, shared RNG via 0x4b6ca0): SmokeUnit RAND/EMIT_SFX, movement, aiming and builder callbacks; compares snapshots, EMIT_SFX lists and final RNG seed" if damaged
			else "Healthy Create, movement, supplied aiming, and builder callbacks when present; excludes firing, damage, destruction and full host timing"), "differences": differences}
	FileAccess.open(folder.path_join(trace_folder + "/native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_MOBILE_COMPARISON%s %d / %d snapshots match; %d units, %d sfx events, %d sfx/seed mismatches" % [" (damaged)" if damaged else "", total - failures, total, index.units.size(), sfx_total, trace_failures])
	quit(0 if failures == 0 and trace_failures == 0 else 1)
