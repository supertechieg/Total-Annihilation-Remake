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
	var guard: int = world.add_unit("corraid", Vector2(512, 512), 0)
	world.units[guard].team = 1
	var ally: int = world.add_unit("corraid", Vector2(560, 512), 0)
	world.units[ally].team = 1
	var first: int = world.add_unit("armflash", Vector2(384, 512), 0)
	var second: int = world.add_unit("armflash", Vector2(512, 368), 0)
	var combat = Combat.new(world)
	combat.gravity = 4369
	var checks := [combat.enable_guard(guard)]
	world.step()
	combat.step()
	checks.append(combat.orders.has(guard) and combat.orders[guard].target == first)
	var initial: int = world.units[first].health
	for step in range(150):
		world.step()
		combat.step()
	checks.append(world.units[first].health < initial)
	world.remove_unit(first)
	for step in range(16):
		world.step()
		combat.step()
	checks.append(combat.orders.has(guard) and combat.orders[guard].target == second)
	world.units[second].position = Vector2(900, 900)
	for step in range(16):
		world.step()
		combat.step()
	checks.append(not combat.orders.has(guard))
	world.remove_unit(guard)
	combat.step()
	checks.append(not combat.guards.has(guard) and not combat.cycles.has(guard))
	var pursuit_world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(64, 64))
	var pursuer: int = pursuit_world.add_unit("corraid", Vector2(512, 512), 0)
	var quarry: int = pursuit_world.add_unit("armflash", Vector2(756, 512), 0)
	pursuit_world.units[pursuer].team = 1
	var pursuit = Combat.new(pursuit_world)
	pursuit.gravity = 4369
	pursuit.enable_guard(pursuer)
	pursuit_world.step()
	pursuit.step()
	checks.append(pursuit.orders.has(pursuer) and pursuit.orders[pursuer].chasing and pursuit.shots_fired == 0)
	var initial_quarry_health: int = pursuit_world.units[quarry].health
	for step in range(360):
		pursuit_world.step()
		pursuit.step()
	checks.append(pursuit_world.units[pursuer].position.x > 512)
	checks.append(pursuit.shots_fired > 0 and pursuit_world.units[quarry].health < initial_quarry_health)
	checks.append(pursuit_world.mobile_units[pursuer].speed == 0 and not pursuit.orders[pursuer].chasing)
	pursuit_world.units[quarry].position = Vector2(900, 900)
	for step in range(16):
		pursuit_world.step()
		pursuit.step()
	checks.append(not pursuit.orders.has(pursuer) and pursuit_world.mobile_units[pursuer].route.is_empty())
	var failures := checks.count(false)
	print("GUARD_COMBAT %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
