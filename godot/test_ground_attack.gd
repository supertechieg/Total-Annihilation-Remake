extends SceneTree
## Ground attack (Suppress 0x4038a0 / target resolver 0x48a1e0): point storage, target height, persistence, approach.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const Mobile = preload("res://mobile_unit.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(40)
	var world = World.new(catalog, Navigation.new(64, 64, heights, 0), Vector2(96, 96))
	var combat = Combat.new(world)
	var order: Dictionary = combat.ground_order(Vector2(300.75, 200.5), 380.0)
	check(order.point == [300, 200] and int(order.approach) == 380, "Ground orders keep the integer X/Z words and start R at the weapon range")
	check(combat.ground_order(Vector2(0, -32768), 1.0).point == [0, -32767], "A Z word of 0x8000 is stored as 0x8001")
	check(Combat.ground_target([300, 200], heights, 64, 64, 0) == [300 << 16, 40 << 16, 200 << 16], "The target Y is the terrain height when above sea level")
	check(Combat.ground_target([300, 200], heights, 64, 64, 40) == [300 << 16, 40 << 16, 200 << 16] and Combat.ground_target([300, 200], heights, 64, 64, 90)[1] == 90 << 16, "Sea level wins unless the terrain is strictly higher")
	check(Combat.ground_target([2000, 200], heights, 64, 64, 5)[1] == 5 << 16, "Outside the map the -1 height gives way to sea level")
	var tank: int = world.add_unit("armstump", Vector2(400, 400), 0.0, 0)
	world.mobile_units[tank] = Mobile.new(world.unit_navigation("armstump"), catalog.definition("armstump"), Vector2(400, 400), world.scripts[tank])
	var enemy: int = world.add_unit("corraid", Vector2(400, 560), 0.0, 1)
	world.collision.sync(world)
	check(combat.enable_guard(tank, true), "The tank guards")
	check(combat.attack_ground(tank, Vector2(400, 520)), "Attack ground is accepted")
	var start: int = combat.shots_fired
	for tick in range(300):
		world.step()
		combat.step()
	check(combat.orders.has(tank) and combat.orders[tank].has("point"), "The ground order persists and is not replaced by the guard's target")
	check(combat.shots_fired - start >= 2, "The unit keeps firing at the point (%d shots)" % (combat.shots_fired - start))
	check(world.units.has(enemy), "Ground fire does not retarget the nearby enemy")
	combat.stop(tank)
	check(not combat.orders.has(tank), "Stop ends the ground attack")
	# An out-of-range point makes the unit approach; each attempt shrinks R by a game-RNG draw below range/3.
	var far := Vector2(400, 900)
	combat.guards.erase(tank)
	check(combat.attack_ground(tank, far), "A far ground point is accepted")
	var before: Vector2 = world.units[tank].position
	var seed_before: int = world.game_random.game_seed
	for tick in range(3):
		world.step()
		combat.step()
	check(bool(combat.orders[tank].chasing) and int(combat.orders[tank].approach) < int(float(catalog.weapon(str(catalog.definition("armstump").weapon1)).definition.range)), "The unit moves toward the point and R shrinks")
	check(world.game_random.game_seed != seed_before, "The approach consumes a game-RNG draw")
	for tick in range(600):
		world.step()
		combat.step()
	check(world.units[tank].position.distance_to(far) < before.distance_to(far), "The unit closes on the far point")
	print("GROUND_ATTACK %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
