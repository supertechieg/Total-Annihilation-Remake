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
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var raider: int = world.add_unit("corraid", Vector2(512, 384), 0)
	var flash: int = world.add_unit("armflash", Vector2(384, 384), 0)
	world.units[raider].team = 1
	var combat = Combat.new(world)
	combat.gravity = 4369
	var checks := [combat.attack(raider, flash)]
	var initial_health: int = world.units[flash].health
	var airborne := false
	var falling := false
	for tick in range(450):
		world.step()
		combat.step()
		for projectile: Dictionary in combat.projectiles:
			airborne = airborne or (projectile.get("ballistic", false) and projectile.velocity_raw[1] > 0)
			falling = falling or (projectile.get("ballistic", false) and projectile.velocity_raw[1] < 0)
		if not world.units.has(flash):
			break
	checks.append(combat.shots_fired > 0 and airborne and falling)
	checks.append(not world.units.has(flash) or world.units[flash].health < initial_health)
	checks.append(combat.cycles[raider].fault.is_empty())
	var duel = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var a: int = duel.add_unit("armflash", Vector2(384, 384), 0)
	var b: int = duel.add_unit("corraid", Vector2(512, 384), 0)
	duel.units[b].team = 1
	var battle = Combat.new(duel)
	battle.gravity = 4369
	var a_health: int = duel.units[a].health
	var b_health: int = duel.units[b].health
	checks.append(battle.attack(a, b) and battle.attack(b, a))
	for step in range(900):
		duel.step()
		battle.step()
		if not duel.units.has(a) or not duel.units.has(b):
			break
	checks.append(not duel.units.has(a) or duel.units[a].health < a_health)
	checks.append(not duel.units.has(b) or duel.units[b].health < b_health)
	checks.append(not duel.units.has(a) or not duel.units.has(b))
	var failures := checks.count(false)
	print("CANNON_COMBAT %d / %d checks pass; shots=%d hits=%d" % [checks.size() - failures, checks.size(), combat.shots_fired, combat.hits])
	quit(0 if failures == 0 else 1)
