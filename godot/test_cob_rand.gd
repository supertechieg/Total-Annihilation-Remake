extends SceneTree
## RAND (0x4b15bd -> 0x4b6c30), EMIT_SFX (vtable+0x30), slot overflow drops (0x4b0b00/0x4b18c2/0x4b192f)
## and the GET_VALUE 4 health read (0x4807ca). Native evidence: analysis/COB_VM_PARITY.md.
const VM = preload("res://cob_vm.gd")
const GameRandom = preload("res://wind_state.gd")
const Cycle = preload("res://weapon_cycle.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func program(routines: Array, names: Array, piece_names: Array = ["body", "flare"], static_count := 1) -> Dictionary:
	var result := {"static_count": static_count, "pieces": piece_names, "functions": [], "instructions": []}
	var pc := 0
	for r in range(routines.size()):
		result.functions.append({"name": names[r], "address": pc})
		for instruction: Array in routines[r]:
			result.instructions.append({"address": pc, "name": instruction[0], "args": instruction[1]})
			pc += 1 + instruction[1].size()
	return result

## Independent transcription of the native 0x4b6c30 multiply-high Park-Miller step (32-bit arithmetic).
static func native_step(seed: int) -> int:
	var s := seed & 0xffffffff
	var high := (s * 0x69c16bd) >> 32
	var q := ((((s - high) & 0xffffffff) >> 1) + high) & 0xffffffff
	q = q >> 16
	var product := (s * 16807) & 0xffffffff
	var correction := ((((-q) & 0xffffffff) << 31) - q) & 0xffffffff
	var next := (product - correction) & 0xffffffff
	if next == 0 or next >= 0x80000000:
		next = (next + 0x7fffffff) & 0xffffffff
	return next

func rand_program() -> Dictionary:
	# RAND(low=static-free constants pushed low then high), result returned.
	return program([
		[["CREATE_LOCAL", []], ["CREATE_LOCAL", []], ["PUSH_LOCAL", [0]], ["PUSH_LOCAL", [1]], ["RAND", []], ["RETURN", []]],
	], ["rand"])

func test_rand_matches_bounded_random() -> void:
	var generator := RandomNumberGenerator.new()
	generator.seed = 0x51fc88
	var mismatches := 0
	for i in range(200000):
		var seed := generator.randi()
		var expected := native_step(seed)
		var shared := GameRandom.new()
		shared.game_seed = seed
		shared.bounded_random(65536)
		if shared.game_seed != expected:
			mismatches += 1
	check(mismatches == 0, "wind_state bounded_random equals native 0x4b6c30 over 200k seeds (%d differ)" % mismatches)
	var vm = VM.new(rand_program())
	var reference := GameRandom.new()
	vm.rng = GameRandom.new()
	vm.rng.game_seed = (0x1234 ^ 0x66e29572) | 1
	reference.game_seed = vm.rng.game_seed
	var ok := true
	for bounds: Array in [[1, 3], [0, 65535], [-100, 100], [7, 7], [-5, -4], [0, 1], [10, 2]]:
		for _repeat in range(20):
			var id: int = vm.invoke("rand", bounds)
			var span: int = VM.i32(int(bounds[1]) - int(bounds[0]) + 1)
			var expected: int = VM.i32(int(bounds[0]) + reference.bounded_random(span))
			if not vm.completions.has(id) or int(vm.completions[id].result) != expected or vm.rng.game_seed != reference.game_seed:
				ok = false
	check(ok and vm.fault.is_empty(), "RAND pops high then low and returns low + bounded_random(high - low + 1)")
	var before: int = vm.rng.game_seed
	for bounds: Array in [[7, 7], [10, 2], [5, 4], [-1, -2]]:
		var id: int = vm.invoke("rand", bounds)
		check(int(vm.completions[id].result) == int(bounds[0]), "RAND bound below 2 returns low (%s)" % [bounds])
	check(vm.rng.game_seed == before, "RAND bound below 2 does not advance the seed")
	var shared := GameRandom.new()
	shared.game_seed = 99
	var a = VM.new(rand_program())
	var b = VM.new(rand_program())
	a.rng = shared
	b.rng = shared
	var first: int = a.completions[a.invoke("rand", [0, 1000])].result
	var second: int = b.completions[b.invoke("rand", [0, 1000])].result
	var replay := GameRandom.new()
	replay.game_seed = 99
	check(first == replay.bounded_random(1001) and second == replay.bounded_random(1001), "Scripts sharing one RNG draw from one sequence")
	var lazy = VM.new(rand_program())
	lazy.invoke("rand", [1, 3])
	check(lazy.fault.is_empty() and lazy.rng != null, "A VM without an injected RNG creates a private one instead of faulting")
	var unseeded := GameRandom.new()
	unseeded.game_seed = 0
	check(unseeded.bounded_random(3) == 0x7fffffff % 3 and unseeded.game_seed == 0x7fffffff, "Seed 0 (unseeded oracle image) degenerates to 0x7fffffff like native")

func test_emit_sfx() -> void:
	var vm = VM.new(program([
		[["PUSH_CONSTANT", [257]], ["EMIT_SFX", [1]], ["PUSH_CONSTANT", [100]], ["SLEEP", []],
			["PUSH_CONSTANT", [3]], ["EMIT_SFX", [0]], ["PUSH_CONSTANT", [0]], ["RETURN", []]],
	], ["smoke"]))
	var calls: Array = []
	vm.sfx_callback = func(piece: int, kind: int) -> void: calls.append([piece, kind])
	vm.invoke("smoke")
	check(vm.sfx_events == [[0, 1, 257]], "EMIT_SFX records [tick, piece, type] and pops the type")
	for _i in range(3):
		vm.step()
	check(vm.sfx_events == [[0, 1, 257], [3, 0, 3]] and vm.sfx_count == 2, "Later EMIT_SFX records the scheduler tick")
	check(calls == [[1, 257], [0, 3]], "Renderer hook receives (piece, type)")
	check(vm.fault.is_empty() and vm.active_threads() == 0, "EMIT_SFX leaves the stack balanced")
	var flood = VM.new(program([[["PUSH_CONSTANT", [1]], ["EMIT_SFX", [0]], ["PUSH_CONSTANT", [0]], ["SLEEP", []], ["JUMP", [0]]]], ["flood"]))
	flood.invoke("flood")
	for _i in range(VM.SFX_EVENT_LIMIT + 10):
		flood.step()
	check(flood.sfx_events.size() == VM.SFX_EVENT_LIMIT and flood.sfx_count == VM.SFX_EVENT_LIMIT + 11, "SFX list stays bounded while the count keeps the total")

func test_overflow_drops() -> void:
	var vm = VM.new(program([
		[["PUSH_CONSTANT", [1000]], ["SLEEP", []], ["PUSH_CONSTANT", [0]], ["RETURN", []]],
		[["PUSH_CONSTANT", [11]], ["PUSH_CONSTANT", [22]], ["START_SCRIPT", [0, 2]], ["PUSH_CONSTANT", [1000]], ["SLEEP", []], ["PUSH_CONSTANT", [0]], ["RETURN", []]],
		[["PUSH_CONSTANT", [33]], ["CALL_SCRIPT", [0, 1]], ["PUSH_CONSTANT", [5]], ["RETURN", []]],
	], ["sleep", "starter", "caller"]))
	for _i in range(6):
		vm.invoke("sleep", [], false)
	vm.invoke("starter", [], false)
	vm.invoke("caller", [], false)
	check(vm.active_threads() == 8, "Eight simultaneous slots available")
	check(vm.invoke("sleep", [], false) == -1 and vm.fault.is_empty() and vm.dropped_calls == 1, "Ninth host start is dropped without a fault")
	vm.step()
	check(vm.fault.is_empty() and vm.dropped_calls == 3, "START_SCRIPT and CALL_SCRIPT with no free slot are dropped")
	var starter: Dictionary = vm.slots[6]
	var caller: Dictionary = vm.slots[7]
	check(int(starter.sp) == 1 and starter.stack[0] == 11 and starter.stack[1] == 22 and starter.state == "sleep", "Dropped START_SCRIPT leaves its arguments on the caller stack and continues")
	check(int(caller.sp) == 0 and caller.stack[0] == 33 and caller.state == "call" and int(caller.wait_slot) == -1, "Dropped CALL_SCRIPT keeps arguments and blocks with wait slot -1")
	for _i in range(40):
		vm.step()
	check(vm.slots[7] != null and vm.slots[7].state == "call", "Finished sleepers do not release a dropped CALL_SCRIPT")
	check(vm.invoke("sleep", [], false) >= 0, "Slots free again accept starts")

func test_health_read() -> void:
	check(VM.health_read(1000, 1000) == 100 and VM.health_read(500, 1000) == 50 and VM.health_read(199, 300) == 66, "Health read truncates health * 100 / maxdamage")
	check(VM.health_read(1, 300) == 0, "Low health reads 0")
	check(VM.health_read(3000, 1000) == 300, "Health read is not clamped at 100")
	check(VM.health_read(-5, 1000) == VM.i32(((-500) & 0xffffffff) / 1000), "Negative health wraps through unsigned division")
	check(VM.health_read(0x10064, 1000) == 10, "Health is read as a signed 16-bit word")

func test_optional_weapon_callbacks() -> void:
	var weapon := {"definition": {"burst": "0"}, "runtime": {"reload_ticks": 30, "velocity_raw_per_tick": 100, "burst_interval_ticks": 1}}
	# corpyro-style: AimPrimary and QueryPrimary, no FirePrimary.
	var vm = VM.new(program([
		[["PUSH_CONSTANT", [1]], ["RETURN", []]],
		[["CREATE_LOCAL", []], ["PUSH_CONSTANT", [1]], ["POP_LOCAL", [0]], ["PUSH_CONSTANT", [0]], ["RETURN", []]],
	], ["AimPrimary", "QueryPrimary"]))
	var cycle = Cycle.new(vm, weapon)
	cycle.aim(0, 0)
	var shots := 0
	for _i in range(70):
		vm.step()
		cycle.step()
		shots += cycle.shots.size()
		if not cycle.shots.is_empty():
			check(int(cycle.shots[0].piece) == 1, "Queried muzzle piece used without FirePrimary")
	check(cycle.fault.is_empty() and shots == 3, "Missing FirePrimary still launches and reloads (%d shots)" % shots)
	var no_aim = VM.new(program([[["PUSH_CONSTANT", [0]], ["RETURN", []]]], ["FirePrimary"]))
	var idle = Cycle.new(no_aim, weapon)
	idle.aim(0, 0)
	shots = 0
	for _i in range(40):
		no_aim.step()
		idle.step()
		shots += idle.shots.size()
	check(idle.fault.is_empty() and shots == 0, "Missing AimPrimary never aims and never fires")
	var no_query = VM.new(program([[["PUSH_CONSTANT", [1]], ["RETURN", []]]], ["AimPrimary"]))
	var fallback = Cycle.new(no_query, weapon)
	fallback.aim(0, 0)
	no_query.step()
	fallback.step()
	check(fallback.fault.is_empty() and fallback.shots.size() == 1 and int(fallback.shots[0].piece) == 0, "Missing QueryPrimary keeps muzzle piece 0")

func run() -> void:
	test_rand_matches_bounded_random()
	test_emit_sfx()
	test_overflow_drops()
	test_health_read()
	test_optional_weapon_callbacks()
	print("COB_RAND_CHECKS %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
