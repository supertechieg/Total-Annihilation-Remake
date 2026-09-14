extends SceneTree
## Replays tools/native_weapon_aim.py through weapon_cycle.gd with the same fake COB responses and compares every tick:
## flags byte, result, stored heading/pitch, reload, Aim/TargetCleared starts (name, args, started), fire attempts,
## launches (stored angles), the unit +0xbb bit 0x10, callback count and the shared RNG seed.
## Inputs taken from the trace: AimFrom/muzzle/SweetSpot points, unit heading/flags, launch results and the 0x49aa80
## range result (the port's host range test is not compared here).
const Cycle = preload("res://weapon_cycle.gd")
const Combat = preload("res://combat_world.gd")
const Reload = preload("res://weapon_reload.gd")
const GameRandom = preload("res://wind_state.gd")
const Ground = preload("res://ground_motion.gd")
const MAP_CELLS := 64

## Eight-slot fake script host mirroring the oracle's fake COB layer.
class FakeVM extends RefCounted:
	var functions := {}
	var completions := {}
	var fault := ""
	var pieces := [{"name": "muzzle"}]
	var slots: Array = []
	var responses: Array = []
	var threads: Array = []
	var full := false
	var next_id := 1
	var callbacks := 0

	func _init(names: Array, response_list: Array) -> void:
		for name in names:
			functions[str(name)] = true
		slots.resize(8)
		responses = response_list.duplicate(true)

	func begin_tick() -> void:
		# The oracle fills every free slot before the weapon update while a 'drop' response is next.
		full = not responses.is_empty() and str(responses[0][0]) == "drop"

	func invoke(name: String, _args: Array = [], _immediate := true) -> int:
		var id := next_id
		next_id += 1
		if name.begins_with("Query"):
			completions[id] = {"locals": [0], "reason": "return", "result": 0}
			return id
		if name.begins_with("Fire"):
			# The oracle's launcher stubs do not start Fire.
			return id
		var response: Array = ["kill", 1]
		if name.begins_with("Aim"):
			response = responses.pop_front() if not responses.is_empty() else ["never"]
		var free := slots.find(null)
		if full or free < 0:
			return -1
		slots[free] = {"id": id}
		threads.append({"id": id, "slot": free, "response": response, "passes": 0, "aim": name.begins_with("Aim")})
		return id

	func step() -> void:
		callbacks = 0
		var survivors: Array = []
		for thread: Dictionary in threads:
			thread.passes = int(thread.passes) + 1
			var kind := str(thread.response[0])
			if (kind == "complete" or kind == "kill") and int(thread.passes) >= int(thread.response[-1]):
				if kind == "complete":
					completions[int(thread.id)] = {"reason": "return", "result": int(thread.response[1]), "locals": []}
					callbacks += 1 if thread.aim else 0
				else:
					completions[int(thread.id)] = {"reason": "signal", "result": 0, "locals": []}
				slots[int(thread.slot)] = null
				continue
			survivors.append(thread)
		threads = survivors

func _initialize() -> void:
	var path := ProjectSettings.globalize_path("res://../local/weapon-aim/native-weapon-aim.json")
	if not FileAccess.file_exists(path):
		printerr("Missing native trace; run python tools/native_weapon_aim.py")
		quit(1)
		return
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var checks := 0
	var matches := 0
	var mismatches: Array = []
	var coverage := {"aim_starts": 0, "dropped": 0, "attempts": 0, "launches": 0, "target_cleared": 0, "range_flags": 0}
	for case: Dictionary in trace.cases:
		var weapon_data: Dictionary = case.weapon
		var flags := int(weapon_data.flags)
		var definition := {"turret": "1" if flags & 0x80000 else "0", "ballistic": "1" if flags & 2 else "0",
			"lineofsight": "1" if flags & 1 else "0", "vlaunch": "1" if flags & 0x10 else "0",
			"tolerance": str(int(weapon_data.tolerance)), "pitchtolerance": str(int(weapon_data.pitch_tolerance)), "accuracy": str(int(weapon_data.accuracy))}
		var runtime := {"reload_ticks": int(weapon_data.reload), "velocity_raw_per_tick": int(weapon_data.speed),
			"minimum_barrel_angle": float(weapon_data.minimum_angle), "burst_interval_ticks": 1}
		var vm := FakeVM.new(case.functions, case.responses)
		var slot_name: String = ["Primary", "Secondary", "Tertiary"][int(case.slot)]
		var cycle = Cycle.new(vm, {"definition": definition, "runtime": runtime}, slot_name)
		var rng := GameRandom.new()
		rng.game_seed = int(case.seed)
		var heights := PackedByteArray()
		for value in case.heights:
			heights.append(int(value))
		var words := [0, 0x8000]
		var case_bad := 0
		for tick in range(case.inputs.size()):
			var inputs: Dictionary = case.inputs[tick]
			var record: Dictionary = case.records[tick]
			if tick > 0:
				vm.step()
				var previous: Dictionary = case.records[tick - 1]
				checks += 1
				if vm.callbacks == previous.callbacks.size():
					matches += 1
				else:
					case_bad += 1
					if mismatches.size() < 12:
						mismatches.append({"case": case.index, "tick": tick - 1, "field": "callbacks", "port": vm.callbacks, "native": previous.callbacks.size()})
			vm.begin_tick()
			if inputs.has("set_target"):
				words = [int(inputs.set_target[0]), int(inputs.set_target[1])]
			var target_state := Cycle.TARGET_VALID
			var target_raw: Array = inputs.target_point
			if int(words[1]) == 0x8000:
				if int(words[0]) == 0:
					target_state = Cycle.TARGET_NONE
				elif int(inputs.alive.get(str(int(words[0])), 1)) == 0:
					target_state = Cycle.TARGET_DEAD
					words = [0, 0x8000]
			else:
				target_raw = Combat.ground_target([Ground.signed16(int(words[0])), Ground.signed16(int(words[1]))], heights, MAP_CELLS, MAP_CELLS, int(case.sea_level))
			var solve := Combat.turret_solve(inputs.aim, target_raw, int(inputs.unit_heading), definition, int(weapon_data.speed), int(case.gravity), float(weapon_data.minimum_angle))
			var muzzle_raw: Array = inputs.muzzle
			var context := {"tick": tick, "target": target_state, "solve": solve, "unit_heading": int(inputs.unit_heading),
				"unit_flags": int(inputs.unit_flags), "in_range": int(record.get("range_ok", 1)) != 0,
				"affordable": float(inputs.energy) >= float(weapon_data.energy) and float(inputs.metal) >= float(weapon_data.metal),
				"launch": int(inputs.launch) != 0, "reload_delay": Reload.ticks(int(weapon_data.reload), int(case.health), int(case.maxdamage), int(case.experience)),
				"line_angles": func(_piece: String) -> Array: return Combat.line_angles(muzzle_raw, target_raw),
				"spread": func(h: int, p: int) -> Array: return Combat.firing_spread(h, p, int(weapon_data.accuracy), int(case.health), int(case.maxdamage), int(case.experience), rng)}
			var launch_attempts := [0]
			cycle.update(context)
			if not cycle.fault.is_empty():
				mismatches.append({"case": case.index, "tick": tick, "fault": cycle.fault})
				case_bad += 1
				break
			var port_starts: Array = []
			var attempts := 0
			for event: Dictionary in cycle.events:
				if event.type == "aim":
					port_starts.append(["Aim" + slot_name, [int(event.args[0]), int(event.args[1])], bool(event.started)])
				elif event.type == "target_cleared":
					port_starts.append(["TargetCleared", [int(case.slot)], bool(event.started)])
				elif event.type == "attempt":
					attempts += 1
			var native_starts: Array = []
			for start: Dictionary in record.starts:
				var count := 2 if str(start.name).begins_with("Aim") else 1
				native_starts.append([str(start.name), start.args.slice(0, count).map(func(v) -> int: return int(v)), bool(start.started)])
			var port_launches: Array = []
			for shot: Dictionary in cycle.shots:
				port_launches.append([int(shot.heading), int(shot.pitch)])
			var native_launches: Array = []
			for item: Dictionary in record.launches:
				if int(item.ok):
					native_launches.append([int(item.heading), int(item.pitch)])
			var fields := {
				"flags": [cycle.flags_byte(), int(record.flags)],
				"result": [cycle.result, int(record.result)],
				"heading": [cycle.heading, int(record.heading)],
				"pitch": [cycle.pitch, int(record.pitch)],
				"reload": [cycle.reload_remaining(), int(record.reload)],
				"starts": [port_starts, native_starts],
				"attempts": [attempts, record.attempts.size()],
				"launches": [port_launches, native_launches],
				"range_flag": [1 if cycle.range_failed else 0, int(record.range_flag)],
				"net": [port_starts.filter(func(s: Array) -> bool: return str(s[0]).begins_with("Aim")).size(), record.net.size()],
				"seed": [rng.game_seed, int(record.seed)]}
			for key: String in fields:
				checks += 1
				var pair: Array = fields[key]
				if JSON.stringify(pair[0]) == JSON.stringify(pair[1]):
					matches += 1
				else:
					case_bad += 1
					if mismatches.size() < 12:
						mismatches.append({"case": case.index, "name": case.get("name", case.get("kind", "")), "tick": tick, "field": key, "port": pair[0], "native": pair[1]})
			coverage.aim_starts += native_starts.filter(func(s: Array) -> bool: return str(s[0]).begins_with("Aim")).size()
			coverage.dropped += native_starts.filter(func(s: Array) -> bool: return str(s[0]).begins_with("Aim") and not s[2]).size()
			coverage.target_cleared += native_starts.filter(func(s: Array) -> bool: return s[0] == "TargetCleared").size()
			coverage.attempts += record.attempts.size()
			coverage.launches += native_launches.size()
			coverage.range_flags += int(record.range_flag)
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "checks": checks, "matching": matches, "coverage": coverage,
		"mismatches": mismatches,
		"scope": "Original 0x49e1a0 per-slot update with 0x48a1e0/0x485070 targets, 0x49aa80 range, 0x49a890/0x4b715a/0x49d910 angle solves, turret callback 0x49d580 (0x49d880 tolerance, 0x4b6c30 spread) and vlaunch callback 0x49db70, script starts through the original 0x4b0a70/0x4b0b00/0x4b08c0 and completion vtable 0x481490; COB threads, piece queries, launchers, payment and network echo replaced by a scripted fake layer"}
	FileAccess.open(ProjectSettings.globalize_path("res://../analysis/native-weapon-aim-validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ", false) + "\n")
	for item in mismatches.slice(0, 6):
		printerr(JSON.stringify(item))
	print("WEAPON_AIM_NATIVE %d / %d checks match" % [matches, checks])
	quit(0 if matches == checks else 1)
