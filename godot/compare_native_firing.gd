extends SceneTree
const VM = preload("res://cob_vm.gd")
const GameRandom = preload("res://wind_state.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/")
	var unit := "armflash"
	var user_args := OS.get_cmdline_user_args()
	var damaged := "--damaged" in user_args
	for candidate: String in ["corraid", "armstump", "armham", "armpw", "armrock", "armwar", "armsam", "armjeth", "corthud", "corlevlr", "corstorm", "cormist", "corcrash", "armfav", "corfav", "corgator", "corak", "armcom", "corcom", "corpyro"]:
		if "--" + candidate in user_args:
			unit = candidate
	var trace_folder := "firing/" + unit if unit != "armflash" else "firing"
	var trace_name := "native-trace-damaged.json" if damaged else "native-trace.json"
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(trace_folder + "/" + trace_name)))
	var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("unit-assets/" + unit + "/script.json")))
	var vm = VM.new(program)
	vm.rng = GameRandom.new()
	vm.rng.game_seed = int(trace.get("seed_start", 0))
	vm.read_values = {4: 100, 17: 0}
	var health: Dictionary = trace.get("health", {})
	var differences: Array = []
	var failures := 0
	for item: Dictionary in trace.snapshots:
		# Latest scheduled health at or before this tick, independent of JSON key order.
		var best := -1
		for key in health:
			if int(key) <= int(item.tick) and int(key) > best:
				best = int(key)
				vm.read_values[4] = int(health[key])
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
			# A dropped query keeps the engine's initial local 0 (native 0x4b0c4f).
			var piece := 0 if invocation < 0 else (int(vm.completions[invocation].locals[0]) if vm.completions.has(invocation) else -999)
			query_matches = piece == int(item.query_piece) and (invocation < 0) == bool(item.get("dropped", false))
		if actual != item.state or not query_matches or not vm.fault.is_empty():
			failures += 1
			if differences.size() < 3:
				differences.append({"tick": item.tick, "action": item.action, "fault": vm.fault, "query_matches": query_matches, "actual": actual, "expected": item.state})
	var trace_matches := true
	if trace.has("sfx"):
		var sfx: Array = JSON.parse_string(JSON.stringify(vm.sfx_events))
		trace_matches = sfx == trace.sfx and vm.sfx_count == trace.sfx.size() and vm.rng.game_seed == int(trace.seed_end) and vm.dropped_calls == trace.get("dropped", []).size()
		if not trace_matches:
			differences.append({"sfx_actual": sfx.slice(0, 8), "sfx_expected": trace.sfx.slice(0, 8), "sfx_count": [vm.sfx_count, trace.sfx.size()],
				"seed": [vm.rng.game_seed, trace.seed_end], "dropped": [vm.dropped_calls, trace.get("dropped", []).size()]})
	var report := {"unit": unit, "snapshots": trace.snapshots.size(), "mismatches": failures, "exe_sha256": trace.exe_sha256,
		"sfx_events": trace.get("sfx", []).size(), "sfx_seed_match": trace_matches, "seed_end": trace.get("seed_end", 0), "dropped_calls": vm.dropped_calls,
		"scope": ("Damaged-seeded 600-tick firing callbacks (health read 100/50/20, shared RNG via 0x4b6ca0): SmokeUnit RAND/EMIT_SFX plus recoil, muzzle visibility and query locals; compares snapshots, EMIT_SFX list and final RNG seed" if damaged
			else "Healthy ground-unit recoil, muzzle visibility, query locals, overlapping firing and optional HitByWeapon callbacks at supplied times; excludes original host cadence/projectiles"),
		"queries": trace.queries, "differences": differences}
	var report_name := "native-comparison-damaged.json" if damaged else "native-comparison.json"
	FileAccess.open(folder.path_join(trace_folder + "/" + report_name), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_FIRING_COMPARISON %s%s: %d / %d snapshots match; sfx %d, sfx/seed %s" % [unit, " damaged" if damaged else "", trace.snapshots.size() - failures, trace.snapshots.size(), trace.get("sfx", []).size(), "match" if trace_matches else "MISMATCH"])
	quit(0 if failures == 0 and trace_matches else 1)
