extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(64, 64))
	var source: int = world.add_unit("armflash", Vector2(256, 512), 0)
	var target: int = world.add_unit("corraid", Vector2(576, 512), 0)
	world.units[target].team = 1
	var combat = Combat.new(world)
	var checks := [combat.attack(source, target, true)]
	world.step()
	combat.step()
	checks.append(combat.orders[source].chasing and combat.shots_fired == 0)
	var destination := Vector2(256, 640)
	checks.append(world.move_unit(source, destination))
	combat.stop(source, false)
	checks.append(not combat.orders.has(source) and not world.mobile_units[source].route.is_empty())
	for tick in range(220):
		world.step()
		combat.step()
	checks.append(world.units[source].position.distance_to(destination) < 5 and combat.shots_fired == 0)
	checks.append(combat.attack(source, target, true))
	world.step()
	combat.step()
	combat.stop(source)
	checks.append(not combat.orders.has(source) and world.mobile_units[source].route.is_empty())
	combat.attack(source, target, true)
	var health: int = world.units[target].health
	for tick in range(450):
		world.step()
		combat.step()
	checks.append(combat.shots_fired > 0 and world.units[target].health < health)
	var failures := checks.count(false)
	print("ATTACK_ORDERS %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
