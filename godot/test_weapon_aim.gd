extends SceneTree
## Rule checks for the original weapon Aim request state machine (0x49e1a0, 0x49d580, 0x49d880, 0x49db70) as ported in
## weapon_cycle.gd: stall after a dropped/zero/killed Aim, tolerance at the fire attempt, re-aim only after the shot or
## a failed check, and no angle-change re-aim. The native per-tick comparison is compare_native_weapon_aim.gd.
const Cycle = preload("res://weapon_cycle.gd")

var passed := 0
var total := 0

## Scripted script host: Aim responses are ["complete", value, passes], ["kill", passes], ["drop"] or ["never"].
class FakeVM extends RefCounted:
	var functions := {}
	var completions := {}
	var fault := ""
	var pieces := [{"name": "muzzle"}]
	var slots: Array = []
	var responses: Array = []
	var threads: Array = []
	var next_id := 1
	var starts: Array = []

	func _init(names: Array, response_list: Array) -> void:
		for name in names:
			functions[str(name)] = true
		slots.resize(8)
		responses = response_list.duplicate(true)

	func invoke(name: String, args: Array = [], immediate := true) -> int:
		var id := next_id
		next_id += 1
		if name.begins_with("Query"):
			completions[id] = {"locals": [0], "reason": "return", "result": 0}
			return id
		var response: Array = ["kill", 1]
		if name.begins_with("Aim"):
			response = responses.pop_front() if not responses.is_empty() else ["complete", 1, 1]
		starts.append({"name": name, "args": args.duplicate(), "immediate": immediate})
		var free := slots.find(null)
		if str(response[0]) == "drop" or free < 0:
			return -1
		slots[free] = {"id": id}
		threads.append({"id": id, "slot": free, "response": response, "passes": 0})
		return id

	func step() -> void:
		var survivors: Array = []
		for thread: Dictionary in threads:
			thread.passes = int(thread.passes) + 1
			var kind := str(thread.response[0])
			if (kind == "complete" or kind == "kill") and int(thread.passes) >= int(thread.response[-1]):
				completions[int(thread.id)] = {"reason": "return" if kind == "complete" else "signal", "result": int(thread.response[1]) if kind == "complete" else 0, "locals": []}
				slots[int(thread.slot)] = null
				continue
			survivors.append(thread)
		threads = survivors

	func aim_starts() -> int:
		return starts.filter(func(s: Dictionary) -> bool: return str(s.name).begins_with("Aim")).size()

func check(condition: bool, label: String) -> void:
	total += 1
	if condition:
		passed += 1
	else:
		printerr("FAILED: " + label)

func make(responses: Array, definition := {}, functions := ["AimPrimary", "QueryPrimary", "FirePrimary"]) -> Array:
	var vm := FakeVM.new(functions, responses)
	var weapon := {"turret": "1", "ballistic": "1", "tolerance": "0", "pitchtolerance": "0"}
	weapon.merge(definition, true)
	var cycle = Cycle.new(vm, {"definition": weapon, "runtime": {"reload_ticks": 6, "velocity_raw_per_tick": 0}})
	return [vm, cycle]

## VM pass, then one weapon update (the host ordering used by combat_world.gd).
func tick(vm: FakeVM, cycle, context: Dictionary) -> void:
	vm.step()
	var full := {"tick": cycle.tick + 1, "target": Cycle.TARGET_VALID, "solve": [true, 1000, 2000]}
	full.merge(context, true)
	cycle.update(full)

func aim_events(cycle) -> Array:
	return cycle.events.filter(func(e: Dictionary) -> bool: return e.type == "aim")

func _initialize() -> void:
	# Dropped start: 0x4b0b00 calls the completion with 0; the request bit is still set (0x49e3ab) and never retried.
	for response: Array in [["drop"], ["complete", 0, 1], ["kill", 2], ["never"]]:
		var pair := make([response])
		var vm: FakeVM = pair[0]
		var cycle = pair[1]
		var shots := 0
		for i in range(120):
			tick(vm, cycle, {})
			shots += cycle.shots.size()
		check(vm.aim_starts() == 1 and cycle.requested and cycle.result == 0 and shots == 0,
			"%s Aim stalls: one start, request kept, result 0, no shot in 120 updates" % response[0])
		check(cycle.flags_byte() == 3, "%s Aim leaves flags byte present|requested" % response[0])
		# Only target loss (0x49e1ea) clears the request; the next update with a target issues Aim again.
		tick(vm, cycle, {"target": Cycle.TARGET_NONE})
		check(not cycle.requested and vm.aim_starts() == 1, "%s Aim: target loss clears the request without a new start" % response[0])
		tick(vm, cycle, {})
		check(vm.aim_starts() == 2 and cycle.requested, "%s Aim: re-issued on the first update after target loss" % response[0])

	# A dead unit target starts TargetCleared(slot) with run-now 0.
	var dead := make([["never"]], {}, ["AimPrimary", "QueryPrimary", "FirePrimary", "TargetCleared"])
	tick(dead[0], dead[1], {})
	tick(dead[0], dead[1], {"target": Cycle.TARGET_DEAD})
	var cleared: Array = dead[0].starts.filter(func(s: Dictionary) -> bool: return s.name == "TargetCleared")
	check(cleared.size() == 1 and cleared[0].args == [0] and not cleared[0].immediate and not dead[1].requested, "Dead target starts TargetCleared(0) with run-now 0 and clears the request")

	# Completion callback 0x481490: any nonzero return stores 1; Aim is started with run-now 0 and heading/pitch args.
	var two := make([["complete", 2, 1]])
	tick(two[0], two[1], {"reload_delay": 6})
	var start: Dictionary = two[0].starts[0]
	check(start.args == [1000, 2000] and not start.immediate and two[1].heading == 1000 and two[1].pitch == 2000, "Aim<slot>(heading, pitch) issued with run-now 0 and angles stored")
	check(two[1].shots.is_empty() and two[1].result == 0, "No shot in the update that issues Aim (the thread has not run yet)")
	tick(two[0], two[1], {"reload_delay": 6})
	check(two[1].shots.size() == 1, "Return value 2 counts as aimed (result = 1) and the next update fires")

	# After a successful shot: result and request cleared, no Aim in the shot update, Aim on the next update.
	var shot_events: Array = aim_events(two[1])
	check(not two[1].requested and two[1].result == 0 and shot_events.is_empty(), "Shot clears result and request without re-aiming in the same update")
	tick(two[0], two[1], {"reload_delay": 6})
	check(aim_events(two[1]).size() == 1 and two[1].requested, "Aim re-issued on the update after the shot")
	check(two[1].reload_remaining() == 5, "Reload word written at the shot counts down once per update")

	# No angle-change retry: while a request is outstanding, new angles do not issue Aim; the tolerance check decides.
	var moving := make([["complete", 1, 3], ["complete", 1, 1]])
	tick(moving[0], moving[1], {"solve": [true, 1000, 2000], "permit": false})
	for i in range(5):
		tick(moving[0], moving[1], {"solve": [true, 1000 + (i + 1) * 400, 2000], "permit": false})
	check(moving[0].aim_starts() == 1 and moving[1].heading == 1000 and moving[1].result == 1, "Changing angles with a request outstanding issues no Aim")
	tick(moving[0], moving[1], {"solve": [true, 1100, 2000]})
	check(moving[1].shots.size() == 1, "Fire attempt within the default 150 tolerance fires on the stale aim")
	for i in range(6):
		tick(moving[0], moving[1], {"solve": [true, 3000, 2000], "permit": false})
	check(moving[0].aim_starts() == 2 and moving[1].result == 1 and moving[1].reload_remaining() == 0, "Second Aim issued after the shot has completed once the reload expires")
	tick(moving[0], moving[1], {"solve": [true, 3200, 2000]})
	check(moving[1].shots.is_empty() and not moving[1].requested and aim_events(moving[1]).is_empty(), "Out-of-tolerance attempt clears the request without re-aiming in that update")
	tick(moving[0], moving[1], {"solve": [true, 3200, 2000]})
	check(aim_events(moving[1]).size() == 1 and moving[1].heading == 3200, "Aim re-issued with fresh angles on the next update after a tolerance failure")

	# 0x49d880 limits.
	check(Cycle.tolerance_ok(0, 0, 150, -150, 0, 0, 0) and not Cycle.tolerance_ok(0, 0, 151, 0, 0, 0, 0), "Default tolerance is 150 on both axes")
	check(not Cycle.tolerance_ok(0, 0, 0, 151, 0, 0, 0), "Default pitch tolerance is 150")
	check(Cycle.tolerance_ok(0, 0, 2000, 2000, 0, 0, 4) and Cycle.tolerance_ok(0, 0, -2000, 0, 0, 0, 8) and not Cycle.tolerance_ok(0, 0, 2001, 0, 0, 0, 0xc), "Unit +0x110 bits 0xc widen the default to 2000")
	check(Cycle.tolerance_ok(0, 0, 700, 700, 700, 0, 0) and not Cycle.tolerance_ok(0, 0, 701, 0, 700, 0, 0), "Explicit tolerance with pitchtolerance 0 uses tolerance for pitch")
	check(Cycle.tolerance_ok(0, 0, 700, 50, 700, 50, 0) and not Cycle.tolerance_ok(0, 0, 0, 51, 700, 50, 0), "Explicit pitchtolerance limits pitch")
	check(Cycle.tolerance_ok(0, 0, 0, 0, 0, 700, 4) and not Cycle.tolerance_ok(0, 0, 0, 2001, 0, 700, 4), "pitchtolerance is ignored when tolerance is 0")
	check(Cycle.tolerance_ok(0xffc0, 0, 0x0040, 0, 0, 0, 0) and Cycle.tolerance_ok(0x8000, 0, 0, 0, 40000, 0, 0), "Differences wrap as signed 16-bit words; tolerance is unsigned")

	# Re-solve failure at the fire attempt: request cleared and unit +0xbb bit 0x10 set.
	var unsolved := make([["complete", 1, 1]])
	tick(unsolved[0], unsolved[1], {"permit": false})
	tick(unsolved[0], unsolved[1], {"solve": [false, 0, 0]})
	check(not unsolved[1].requested and unsolved[1].range_failed and unsolved[1].shots.is_empty(), "Failed re-solve clears the request and sets the range flag")
	tick(unsolved[0], unsolved[1], {"solve": [false, 0, 0]})
	check(unsolved[0].aim_starts() == 1 and not unsolved[1].requested, "No Aim while the turret solve fails")

	# Launch failure: request and result kept, stored heading already made absolute (0x49d6b4) before the launcher.
	var failed := make([["complete", 1, 1]])
	tick(failed[0], failed[1], {"permit": false})
	tick(failed[0], failed[1], {"launch": false, "unit_heading": 5000})
	check(failed[1].requested and failed[1].result == 1 and failed[1].heading == 6000 and failed[1].shots.is_empty(), "Failed launch keeps request/result with the absolute stored heading")
	tick(failed[0], failed[1], {"unit_heading": 5000})
	check(failed[1].shots.is_empty() and not failed[1].requested, "The absolute heading then fails the tolerance check")

	# Vlaunch callback 0x49db70: Aim(0, 0), gated only by result.
	var vlaunch := make([["complete", 1, 1]], {"turret": "0", "ballistic": "0", "vlaunch": "1"})
	tick(vlaunch[0], vlaunch[1], {"line_angles": func(_p: String) -> Array: return [123, 456]})
	check(vlaunch[0].starts[0].args == [0, 0] and vlaunch[1].requested, "Vlaunch issues Aim(0, 0)")
	tick(vlaunch[0], vlaunch[1], {"line_angles": func(_p: String) -> Array: return [123, 456]})
	check(vlaunch[1].shots.size() == 1 and vlaunch[1].heading == 123 and vlaunch[1].pitch == 456 and not vlaunch[1].requested and vlaunch[1].result == 0, "Vlaunch fires on result, stores line angles, clears result and request")

	# Missing Aim function behaves like a dropped start: request set, never aimed.
	var missing := make([], {}, ["QueryPrimary", "FirePrimary"])
	for i in range(30):
		tick(missing[0], missing[1], {})
	check(missing[1].requested and missing[1].result == 0 and missing[0].aim_starts() == 0 and missing[1].shots.is_empty(), "Undefined Aim sets the request bit and never fires")

	# Fire is started with run-now 0 after the shot.
	var fire: Array = two[0].starts.filter(func(s: Dictionary) -> bool: return s.name == "FirePrimary")
	check(fire.size() == 1 and not fire[0].immediate, "Fire<slot> started with run-now 0 after the launch")

	print("WEAPON_AIM %d / %d checks pass" % [passed, total])
	quit(0 if passed == total else 1)
