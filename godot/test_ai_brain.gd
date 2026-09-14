extends SceneTree
## AI CP1/CP7 fixtures for ai_brain.gd (brain 0x408cb0/0x408c40, caller filter 0x464f80, groups 0x408830/0x480250).
const AIBrain = preload("res://ai_brain.gd")
const GameRandom = preload("res://wind_state.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

static func park_miller(state: int) -> int:
	var next := (state * 16807) % 2147483647
	return 2147483647 if next == 0 else next

func test_rng() -> void:
	var rng := GameRandom.new()
	rng.game_seed = 12345
	check(rng.bounded_random(1) == 0 and rng.bounded_random(0) == 0 and rng.bounded_random(-7) == 0 and rng.game_seed == 12345,
		"0x4b6c30: n < 2 (signed) returns 0 without advancing the state")
	var value := rng.bounded_random(900)
	check(rng.game_seed == park_miller(12345) and value == park_miller(12345) % 900, "0x4b6c30: n >= 2 advances once, returns state % n")

func test_filters() -> void:
	check(AIBrain.runs_player_step({"p0": 1, "type": 2, "side": 0}), "type-2 present player is stepped")
	check(AIBrain.runs_player_step({"p0": 1, "type": 1, "side": 3}) and AIBrain.runs_player_step({"p0": 1, "type": 3, "side": 3}), "types 1 and 3 are stepped")
	check(not AIBrain.runs_player_step({"p0": 0, "type": 2, "side": 0}), "record word 0 skips the player")
	check(not AIBrain.runs_player_step({"p0": 1, "type": 0, "side": 0}) and not AIBrain.runs_player_step({"p0": 1, "type": 4, "side": 0}), "types outside 1..3 are skipped")
	check(not AIBrain.runs_player_step({"p0": 1, "type": 2, "side": 10}), "side byte 10 is skipped")
	check(AIBrain.creates_brain({"p0": 1, "type": 2}) and AIBrain.creates_brain({"p0": 0, "type": 3}) and not AIBrain.creates_brain({"p0": 1, "type": 3}),
		"0x46489d: brain unless present type 3")
	check(not AIBrain.creates_brain({"p0": 1, "type": 0x103}) and AIBrain.runs_player_step({"p0": 1, "type": 0x102, "side": 0x10b})
		and not AIBrain.runs_player_step({"p0": 1, "type": 0x104, "side": 0}) and not AIBrain.runs_player_step({"p0": 1, "type": 2, "side": 0x10a}), "type and side compare as bytes everywhere")

func test_construction() -> void:
	var brain := AIBrain.new(4, 4096, 3072, GameRandom.new())
	check(brain.countdown == 30 and brain.build_block_tick == 0 and brain.weapon_cursor == 0 and brain.handlers[0] == null, "brain fields and null slot 0")
	var ok := true
	for slot in range(1, 10):
		ok = ok and brain.handlers[slot].group == slot and brain.handlers[slot].wake == 0 and brain.handlers[slot].side == 4
	check(ok, "handler k serves group k with wake 0 and side copy")
	check(brain.handlers[2].params == [3, 6, 20000, 3, 0] and brain.handlers[6].params == [3, 6, 50000, 7, 0], "attack handler params")
	check(brain.handlers[3].params == [2] and brain.handlers[7].params == [6], "feeders point at slots 2 and 6")
	check(brain.handlers[9].params == [2048 << 16, 0, 1536 << 16, 2048 << 16, 0, 1536 << 16, 2048 << 16, 0, 1536 << 16, 0], "hunter centre from map size")
	check(AIBrain.new(0, 7, -3).handlers[9].params[0] == 3 << 16 and AIBrain.new(0, 7, -3).handlers[9].params[2] == -65536, "hunter halves truncate toward zero")

func test_cadence() -> void:
	var rng := GameRandom.new()
	rng.game_seed = 777
	var brain := AIBrain.new(0, 2048, 2048, rng)
	var player := {"p0": 1, "type": 2}
	var counts := {}
	var assigns: Array = []
	var expected := GameRandom.new()
	expected.game_seed = 777
	var first := brain.tick(0, player)
	var air := expected.bounded_random(900)
	var hunter := expected.bounded_random(150)
	var slots := first.filter(func(e): return e[0] == "think").map(func(e): return e[1])
	check(slots == [1, 2, 3, 4, 5, 6, 7, 8, 9], "first tick runs every handler in slot order")
	check(first.back() == ["weapons", 1], "type-2 brain tick ends with weapon scheduler(1)")
	check(brain.handlers[8].wake == 30 + air and brain.handlers[9].wake == 30 + hunter and rng.game_seed == expected.game_seed,
		"group 8 draws rand(900) before group 9 rand(150); wake = tick + 30 + rand")
	check(brain.handlers[1].wake == 30 and brain.handlers[2].wake == 300 and brain.handlers[3].wake == 150 and brain.handlers[4].wake == 90 and brain.handlers[5].wake == 0,
		"periods 30/300/150/90, group 5 never sets wake")
	for tick in range(1, 901):
		for event: Array in brain.tick(tick, player):
			if event[0] == "think":
				counts[event[1]] = counts.get(event[1], 0) + 1
			elif event[0] == "assign":
				assigns.append(tick)
	check(counts.get(5, 0) == 900, "group 5 no-op is called on every tick")
	check(counts.get(1, 0) == 30 and counts.get(4, 0) == 10 and counts.get(3, 0) == 6 and counts.get(2, 0) == 3, "group 1/2/3/4 cadence over 900 ticks")
	check(assigns.size() == 30 and assigns[0] == 29 and assigns[1] == 59, "assign_groups on the 30th brain tick then every 30")
	var idle := AIBrain.new(0, 0, 0, rng)
	var seed_before: int = rng.game_seed
	var events := idle.tick(0, {"p0": 1, "type": 1})
	check(events == [["weapons", 0]] and idle.countdown == 30 and rng.game_seed == seed_before, "type 1: only weapon scheduler(0), no countdown, no draws")
	check(idle.tick(0, {"p0": 0, "type": 2}) == [["weapons", 0]], "type 2 with record word 0: scheduler(0) only")
	var edge := AIBrain.new(0, 0, 0, rng)
	edge.handlers[1].wake = 0x80000000
	check(edge.tick(0x7fffffff, player).filter(func(e): return e[0] == "think" and e[1] == 1).is_empty(), "wake compare is unsigned (0x80000000 > 0x7fffffff)")
	edge.handlers[1].wake = 0
	edge.tick(0xfffffff0, player)
	check(edge.handlers[1].wake == 0x0e, "wake wraps modulo 2^32")
	edge.countdown = -4
	check(edge.tick(1, player)[0] == ["assign"] and edge.countdown == 30, "countdown <= 0 after decrement resets to 30 and assigns")
	var hooked := AIBrain.new(0, 0, 0, rng)
	var seen: Array = []
	hooked.think_hooks[4] = func(b, handler, t): seen.append([handler.wake, t])
	hooked.tick(10, player)
	check(seen == [[100, 10]], "think hook runs after the native prologue wake store")
	var bare := AIBrain.new(0, 0, 0)
	var bare_events := bare.tick(5, player)
	check(bare.rng != null and bare.handlers[8].wake >= 35 and bare.handlers[8].wake < 935 and bare_events.back() == ["weapons", 1],
		"brain without a random source reports an error and uses a private stream instead of crashing")

func unit(flags: int, group: int, type: Variant) -> Dictionary:
	return {"flags110": flags, "group": group, "type": type}

func test_assign() -> void:
	var defs := {
		"land": {"minwaterdepth": -10000},
		"builder": {"builder": true, "minwaterdepth": -10000},
		"air_builder": {"builder": true, "canfly": true},
		"sea_builder": {"builder": true, "minwaterdepth": 12},
		"flyer": {"canfly": true, "minwaterdepth": 30},
		"ship": {"minwaterdepth": 8},
		"zero": {"minwaterdepth": 0},
		"wrap": {"minwaterdepth": 0x10005},
		"negative_word": {"minwaterdepth": 0x8001},
		"commander": {"builder": true, "cancapture": true, "flags241": 0x10040, "flags245": 0x1010},
	}
	var armed := 0x80000000 | 0x20
	var units := [
		unit(0x20000000 | armed, 0, "land"), unit(0x20000000 | 0x20, 0, "land"), unit(0x20, 0, "builder"), unit(0x20, 0, "air_builder"),
		unit(0x20, 0, "sea_builder"), unit(armed, 0, "flyer"), unit(0x20, 0, "ship"), unit(armed, 0, "zero"), unit(0x20, 0, "zero"),
		unit(0x20, 0, "wrap"), unit(armed, 0, "negative_word"), unit(armed, 0, "commander"), unit(armed, 3, "ship"), unit(0x20000000 | armed & ~0x20, 0, "land"),
		unit(0x3c0020, 0x100, "ship"), unit(0x1f0020, -1, "land"),
	]
	var lists: Array = [range(16), [], [], [12], [], [], [], [], [], []]
	var result := AIBrain.assign_groups(units, defs, lists, range(16))
	check(result.groups == [5, 1, 4, 4, 4, 8, 7, 3, 0, 7, 3, 4, 3, 0, 0x100, -1], "group selection order: structure, builder, canfly, minwaterdepth > 0 (s16), armed")
	check(units[0].flags110 & 0x3c0000 == 0x280000 and units[11].flags110 & 0x3c0000 == 0x240000, "ROAM / MANEUVER (cancapture) and FIRE AT WILL written")
	check(units[15].flags110 & 0x3c0000 == 0x280000 and units[14].flags110 & 0x3c0000 == 0x280000, "any prior 2-bit state becomes ROAM/FIRE AT WILL; grouped units still get state writes")
	check(units[13].flags110 == (0x20000000 | 0x80000000), "flag 0x20 clear: no state write and no group")
	var remaining: Array = lists[0].duplicate()
	remaining.sort()
	check(remaining == [8, 12, 13, 14, 15] and lists[5] == [0] and lists[1] == [1] and lists[8] == [5], "only reassigned units leave the group 0 list")
	check(lists[3] == [12, 7, 10] and lists[4] == [2, 3, 4, 11] and lists[7] == [6, 9], "units append to group lists in range order")
	var swap := [unit(0x20, 0, "builder"), unit(0x20, 0, "land"), unit(0x20, 0, "land"), unit(0x20, 0, "land")]
	var swap_lists: Array = [[1, 0, 2, 3], [], [], [], [], [], [], [], [], []]
	AIBrain.assign_groups(swap, defs, swap_lists, range(4))
	check(swap_lists[0] == [1, 3, 2] and swap_lists[4] == [0], "0x480250 removal moves the last member into the vacated slot")
	var missing: Array = [[1], [], [], [], [], [], [], [], [], []]
	AIBrain.assign_groups([unit(0x20, 0, "builder")], defs, missing, [0])
	check(missing[0] == [1] and missing[4] == [0], "unit absent from its old list is still appended to the new one")
	var calls := AIBrain.assign_groups([unit(0x20, 0, "builder"), unit(0x20, 0, "land")], defs)
	check(calls.calls == [[0, 4]] and calls.flags110 == [0x280020, 0x280020], "ungrouped unarmed land unit is not assigned")
	check(AIBrain.creation_flags(0x4000, {"bmcode": 0}) == 0x30010021 and AIBrain.creation_flags(0x20000000, {"bmcode": 1}) == 0x10010021,
		"creation flags: active, bmcode==0 structure bit, 0x10021")
	check(AIBrain.creation_flags(0x1e, {"bmcode": 1}) == 0x10010021 and AIBrain.creation_flags(0xffffffff, {"bmcode": 0}) == 0x3001b0e1,
		"0x485b4c mask 0xfffdf3e1 and the later clears remove prior bits")
	check(AIBrain.creation_flags(0, {"flags241": 0x10000}) == 0x90010021 and AIBrain.creation_flags(0x80000000, {"flags241": 0xfffe0000}) == 0x10010021,
		"bit 31 armed = def+0x241 bit 16 only (shl 0xf drops bits 17..31, old bit 31 cleared)")
	check(AIBrain.creation_flags(0x40000000, {"flags241": 0x200}) == 0x50010021 and AIBrain.creation_flags(0x40000000, {}) == 0x10010021,
		"bit 30 = def+0x241 bit 9")
	check(AIBrain.creation_flags(0, {"flags241": 0x15}, true) == 0x10150a21, "local side bit 9, move/fire state from def+0x241 bits 0..3, bit 11 from bit 4")
	check(AIBrain.creation_flags(0x3000000, {"byte22e": 2}) == 0x10c10021 and AIBrain.creation_flags(0xffffffff, {"bmcode": 1, "flags241": 0xffffffff, "byte22e": 0x101}, true) == 0xd03dbae1,
		"def+0x22e byte > 1 sets bits 22/23 and clears 24/25; otherwise 22..25 cleared")

func _init() -> void:
	test_rng()
	test_filters()
	test_construction()
	test_cadence()
	test_assign()
	print("AI_BRAIN %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
