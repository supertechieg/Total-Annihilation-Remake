extends SceneTree
const VM = preload("res://cob_vm.gd")
const GameRandom = preload("res://wind_state.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var damaged := "--damaged" in OS.get_cmdline_user_args()
	var failures := 0
	var total := 0
	var sfx_total := 0
	var trace_failures := 0
	var differences: Array = []
	var executable_hash := ""
	var units: Array = ["armvp", "armlab", "corvp", "corlab"] if damaged else ["armvp", "armlab", "corvp", "corlab", "spin0", "spin1", "spin2", "spin3", "spin4", "spin5"]
	for unit: String in units:
		var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("factory/%s-trace%s.json" % [unit, "-damaged" if damaged else ""])))
		var health: Dictionary = trace.get("health", {})
		if trace.has("exe_sha256"):
			executable_hash = trace.exe_sha256
		var program: Dictionary = trace.program if trace.has("program") else JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/%s/script.json" % unit)))
		var vm = VM.new(program)
		vm.rng = GameRandom.new()
		vm.rng.game_seed = int(trace.get("seed_start", 0))
		vm.read_values = {4: 100, 17: 100}
		vm.writable_values.assign([5, 18, 19])
		vm.readback_values.assign([18])
		for item: Dictionary in trace.snapshots:
			if int(item.tick) >= 30:
				vm.read_values[17] = 0
			# Latest scheduled health at or before this tick, independent of JSON key order.
			var best := -1
			for key in health:
				if int(key) <= int(item.tick) and int(key) > best:
					best = int(key)
					vm.read_values[4] = int(health[key])
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
		if trace.has("sfx"):
			var sfx: Array = JSON.parse_string(JSON.stringify(vm.sfx_events))
			sfx_total += trace.sfx.size()
			if sfx != trace.sfx or vm.sfx_count != trace.sfx.size() or vm.rng.game_seed != int(trace.seed_end) or vm.dropped_calls != trace.get("dropped", []).size():
				trace_failures += 1
				differences.append({"unit": unit, "sfx_actual": sfx.slice(0, 8), "sfx_expected": trace.sfx.slice(0, 8), "seed": [vm.rng.game_seed, trace.seed_end]})
	var report := {"snapshots": total, "mismatches": failures, "exe_sha256": executable_hash, "sfx_events": sfx_total, "sfx_seed_mismatches": trace_failures,
		"scope": "Damaged-seeded 600-tick factory lifecycle (health read 100/50/20, shared RNG via 0x4b6ca0): SmokeUnit RAND/EMIT_SFX, snapshots, EMIT_SFX lists and final RNG seed" if damaged else "Original Arm and Core vehicle plant and Kbot lab healthy script playback with immediate clear-yard acknowledgements, plus six synthetic spin cases; not world production timing, combat or Core aircraft/naval/advanced factory", "differences": differences}
	FileAccess.open(folder.path_join("factory/native-comparison%s.json" % ("-damaged" if damaged else "")), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_FACTORY_COMPARISON%s %d / %d snapshots match; %d sfx events, %d sfx/seed mismatches" % [" (damaged)" if damaged else "", total - failures, total, sfx_total, trace_failures])
	quit(0 if failures == 0 and trace_failures == 0 else 1)
