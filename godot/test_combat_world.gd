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
	check(not combat.attack(world.builder_id, target), "Unsupported weapon source is explicit")
	check(not combat.attack(source, world.builder_id), "Friendly attack order is rejected")
	check(combat.attack(source, target), "Flash accepts enemy target")
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
	for tick in range(30):
		world.step()
		combat.step()
	check(combat.shots_fired == count, "Stop cancels new shots while existing projectiles finish")
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
	check(is_equal_approx(Combat.segment_sphere(Vector3.ZERO, Vector3(100, 0, 0), Vector3(50, 0, 0), 1), 0.49), "Swept collision catches a target between endpoints")
	check(is_inf(Combat.segment_sphere(Vector3.ZERO, Vector3(100, 0, 0), Vector3(50, 5, 0), 1)), "Near miss stays a miss")
	check(Combat.segment_sphere(Vector3.ZERO, Vector3(10, 0, 0), Vector3.ZERO, 1) == 0, "Inside-volume shot contacts immediately")
	var far: int = world.add_unit("corraid", Vector2(512, 256), 0.0)
	var near: int = world.add_unit("corraid", Vector2(448, 256), 0.0)
	combat.projectiles = [{"source": source, "position": Vector3(384, 12, 256), "previous": Vector3(384, 12, 256),
		"position_raw": Combat.raw_point(Vector3(384, 12, 256)), "velocity_raw": [13107200, 0, 0], "distance": 0.0, "range": 250.0, "damage": {"default": "8"}}]
	combat.step()
	check(world.units[near].health == 1050 and world.units[far].health == 1058, "Nearest swept contact wins regardless of insertion order")
	combat.projectiles = [{"source": source, "position": Vector3(100, 100, 700), "previous": Vector3(100, 100, 700),
		"position_raw": Combat.raw_point(Vector3(100, 100, 700)), "velocity_raw": [655359, 0, 0], "distance": 0.0, "range": 100.0, "damage": {"default": "8"}}]
	for tick in range(3):
		combat.step()
	check(combat.projectiles[0].position_raw[0] == 100 * 65536 + 3 * 655359, "Projectile integration retains fixed-point speed precision")
	for tick in range(20):
		combat.step()
	check(combat.projectiles.is_empty(), "Range-limited projectiles expire")
	var unfinished: int = world.begin_build("armsolar", Vector2(192, 128))
	world.remove_unit(unfinished)
	check(unfinished > 0 and world.task_id == 0 and not world.units.has(unfinished), "Destroyed construction target clears builder reference")
	print("COMBAT_WORLD %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
