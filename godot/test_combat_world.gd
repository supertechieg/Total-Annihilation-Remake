extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const Mobile = preload("res://mobile_unit.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
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
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var source: int = world.add_unit("armflash", Vector2(384, 256), 0.0)
	world.mobile_units[source] = Mobile.new(world.unit_navigation("armflash"), catalog.definition("armflash"), Vector2(384, 256), world.scripts[source])
	var target: int = world.add_unit("corraid", Vector2(512, 256), 0.0)
	world.units[target].team = 1
	var combat = Combat.new(world)
	check(world.units[source].has("weapon_launch_offset"), "Weapon offset is captured during unit creation")
	var initial_offset: int = world.units[source].weapon_launch_offset
	check(not combat.attack(world.builder_id, target), "Unsupported weapon source is explicit")
	check(not combat.attack(source, world.builder_id), "Friendly attack order is rejected")
	check(combat.attack(source, target), "Flash accepts enemy target")
	check(int(combat.launch_offsets[source]) == initial_offset, "First attack keeps creation offset despite mobile heading changes")
	world.step()
	combat.step()
	check(combat.shots_fired == 0, "Aiming gates projectile creation")
	var initial_health: int = world.units[target].health
	for tick in range(150):
		world.step()
		combat.step()
	check(combat.shots_fired > 0 and combat.hits > 0, "Scripted bursts produce projectile hits")
	check(world.units.has(target) and world.units[target].health < initial_health, "Impacts reduce target health")
	check(combat.cycles[source].fault.is_empty(), "Combat leaves the firing VM fault-free")
	combat.stop(source)
	var count: int = combat.shots_fired
	var pending_rounds := 0
	for burst: Dictionary in combat.bursts:
		pending_rounds += int(burst.state.remaining)
	for tick in range(30):
		world.step()
		combat.step()
	check(combat.shots_fired == count + pending_rounds and combat.bursts.is_empty(), "Stop prevents dispatch while already-created burst rounds finish")
	count = combat.shots_fired
	world.units[target].position = Vector2(800, 256)
	combat.attack(source, target)
	for tick in range(80):
		world.step()
		combat.step()
	check(combat.shots_fired == count, "Out-of-range target cannot be fired on")
	world.units[target].position = Vector2(512, 256)
	for tick in range(1200):
		world.step()
		combat.step()
		if not world.units.has(target):
			break
	check(not world.units.has(target), "Sustained hits destroy target")
	world.step()
	combat.step()
	check(not combat.orders.has(source), "Destroyed target clears its attack order")
	var far: int = world.add_unit("corraid", Vector2(512, 256), 0.0)
	var near: int = world.add_unit("corraid", Vector2(448, 256), 0.0)
	world.units[far].team = 1
	world.units[near].team = 1
	check(world.collision.target_at(world, Combat.raw_point(Vector3(448, 5, 256)), 0) == near, "Endpoint cell selects its enemy occupant")
	check(world.collision.target_at(world, Combat.raw_point(Vector3(448, 5, 256)), 1) == 0, "Same-owner occupant is ignored")
	check(world.collision.target_at(world, Combat.raw_point(Vector3(448, 12, 256)), 0) == 0, "Shot above native model height misses")
	combat.projectiles = [{"source": source, "owner": 0, "position": Vector3(384, 12, 256), "previous": Vector3(384, 12, 256),
		"position_raw": Combat.raw_point(Vector3(384, 12, 256)), "velocity_raw": [13107200, 0, 0], "distance": 0.0, "range": 250.0, "damage": {"default": "8"}}]
	combat.step()
	check(world.units[near].health == 1058 and world.units[far].health == 1058, "Native endpoint rule does not sweep intervening units")
	combat.projectiles = [{"source": source, "owner": 0, "position": Vector3(438, 5, 256), "previous": Vector3(438, 5, 256),
		"position_raw": Combat.raw_point(Vector3(438, 5, 256)), "velocity_raw": [655360, 0, 0], "distance": 0.0, "range": 100.0, "damage": {"default": "8"}}]
	combat.step()
	check(world.units[near].health == 1050 and world.units[far].health == 1058, "Endpoint impact damages only the selected cell occupant")
	combat.projectiles = [{"source": source, "owner": 0, "position": Vector3(100, 100, 700), "previous": Vector3(100, 100, 700),
		"position_raw": Combat.raw_point(Vector3(100, 100, 700)), "velocity_raw": [655359, 0, 0], "distance": 0.0, "range": 100.0, "damage": {"default": "8"}}]
	for tick in range(3):
		combat.step()
	check(combat.projectiles[0].position_raw[0] == 100 * 65536 + 3 * 655359, "Projectile integration retains fixed-point speed precision")
	for tick in range(20):
		combat.step()
	check(combat.projectiles.is_empty(), "Range-limited projectiles expire")
	combat.bursts.clear()
	combat.projectiles = [{"source": source, "owner": 0, "position": Vector3(100, 100, 700), "previous": Vector3(100, 100, 700),
		"position_raw": Combat.raw_point(Vector3(100, 100, 700)), "velocity_raw": [655359, 0, 0], "distance": 0.0, "range": 1.0, "deadline": combat.tick + 3, "damage": {"default": "8"}}]
	combat.step()
	combat.step()
	check(combat.projectiles.size() == 1 and int(combat.projectiles[0].position_raw[0]) == 100 * 65536 + 2 * 655359, "Timed rounds travel beyond nominal range before deadline")
	combat.step()
	check(combat.projectiles.is_empty(), "Timed round expires before movement on its deadline")
	var unfinished: int = world.begin_build("armsolar", Vector2(192, 128))
	world.remove_unit(unfinished)
	check(unfinished > 0 and world.task_id == 0 and not world.units.has(unfinished), "Destroyed construction target clears builder reference")
	print("COMBAT_WORLD %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
