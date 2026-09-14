extends SceneTree
## Self-destruct (0x402010): countdown runs, the game-RNG final wait, reason-3 death with selfdestructas, cancel rules.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const GameRandom = preload("res://wind_state.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func setup(catalog: RefCounted) -> Array:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(96, 96))
	var combat = Combat.new(world)
	world.game_random.game_seed = 12345
	return [world, combat]

func run_until_dead(world: RefCounted, combat: RefCounted, id: int, limit := 400) -> int:
	for tick in range(limit):
		world.step()
		combat.step()
		if not world.units.has(id):
			return combat.tick
	return -1

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	check(Combat.self_destruct_countdown({}) == 5 and Combat.self_destruct_countdown({"selfdestructcountdown": "13"}) == 5 and Combat.self_destruct_countdown({"selfdestructcountdown": "2"}) == 2, "Countdown is the low 3 bits of selfdestructcountdown, default 5")
	var pair := setup(catalog)
	var world = pair[0]
	var combat = pair[1]
	var flash: int = world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
	world.collision.sync(world)
	check(combat.toggle_self_destruct([flash]), "Ctrl+D starts the order")
	var expected_rng := GameRandom.new()
	expected_rng.game_seed = world.game_random.game_seed
	var wait := expected_rng.bounded_random(15)
	var started: int = combat.tick
	var died := run_until_dead(world, combat, flash)
	var voices: Array = combat.voice_requests.map(func(entry: Array): return entry[1])
	check(voices == ["count5", "count4", "count3", "count2", "count1", "count0"], "Voice lines count 5 down to 0: %s" % [voices])
	# The expired run sleeps rand(15) ticks; the kill runs on the first later update (next tick when the draw is 0).
	check(died - started == 151 + maxi(1, wait), "Death lands 30 ticks per count plus the RNG wait after the first run (%d vs %d)" % [died - started, 151 + maxi(1, wait)])
	check(world.game_random.game_seed == expected_rng.game_seed, "The final wait consumes exactly one game-RNG draw")
	var death: Dictionary = combat.deaths[-1]
	check(death.type == "armflash" and int(death.severity) >= 1, "The unit dies through the normal severity path")
	# Cancel before expiry plays canceldestruct; cancel after expiry detonates at once.
	pair = setup(catalog)
	world = pair[0]
	combat = pair[1]
	var raider: int = world.add_unit("corraid", Vector2(512, 512), 0.0, 1)
	world.collision.sync(world)
	combat.toggle_self_destruct([raider])
	for tick in range(40):
		world.step()
		combat.step()
	check(not combat.toggle_self_destruct([raider]) and not combat.self_destructs.has(raider) and world.units.has(raider), "A second Ctrl+D cancels the countdown")
	check(combat.voice_requests[-1] == [raider, "canceldestruct"], "Cancelling after the first run plays canceldestruct")
	combat.toggle_self_destruct([raider])
	for tick in range(151):
		world.step()
		combat.step()
	check(combat.self_destructs.has(raider) and bool(combat.self_destructs[raider].expired), "The order is expired during the final random wait")
	combat.toggle_self_destruct([raider])
	combat.process_deaths()
	check(not world.units.has(raider), "Cancelling during the final wait detonates immediately")
	# Mixed selection: removing only from units that have the order.
	pair = setup(catalog)
	world = pair[0]
	combat = pair[1]
	var a: int = world.add_unit("armflash", Vector2(400, 400), 0.0, 1)
	var b: int = world.add_unit("armflash", Vector2(600, 600), 0.0, 1)
	world.collision.sync(world)
	combat.toggle_self_destruct([a])
	check(not combat.toggle_self_destruct([a, b]) and not combat.self_destructs.has(a) and not combat.self_destructs.has(b), "Ctrl+D over a selection containing an ordered unit cancels instead of adding")
	check(combat.voice_requests.is_empty(), "Cancelling before the first run is silent")
	print("SELF_DESTRUCT %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
