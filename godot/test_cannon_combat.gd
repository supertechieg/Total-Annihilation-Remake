extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")

func _initialize() -> void:
	var cannon_type := "armwar" if "--armwar" in OS.get_cmdline_user_args() else "corraid"
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var raider: int = world.add_unit(cannon_type, Vector2(512, 384), 0)
	var flash: int = world.add_unit("armflash", Vector2(384, 384), 0)
	world.units[raider].team = 1
	var combat = Combat.new(world)
	var sound_events: Array = []
	combat.sound_requested.connect(func(name: String, position: Vector3) -> void: sound_events.append({"name": name, "position": position}))
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
	var b: int = duel.add_unit(cannon_type, Vector2(512, 384), 0)
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
	for offset: Vector2 in [Vector2(128, 0), Vector2(-128, 0), Vector2(0, 128), Vector2(0, -128)]:
		var arena = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
		var shooter: int = arena.add_unit(cannon_type, Vector2(512, 512), 0)
		var victim: int = arena.add_unit("armflash", Vector2(512, 512) + offset, 0)
		arena.units[shooter].team = 1
		var firing = Combat.new(arena)
		firing.gravity = 4369
		var health: int = arena.units[victim].health
		firing.attack(shooter, victim)
		for step in range(300):
			arena.step()
			firing.step()
			if not arena.units.has(victim):
				break
		var damaged: bool = not arena.units.has(victim) or arena.units[victim].health < health
		checks.append(damaged)
		if not damaged:
			printerr("Cannon direction missed: ", offset, " shots=", firing.shots_fired)
	for elevation in [8, 24]:
		var terrain_heights := heights.duplicate()
		for z in range(28, 37):
			for x in range(38, 46):
				terrain_heights[z * 64 + x] = elevation
		var arena = World.new(catalog, Navigation.new(64, 64, terrain_heights), Vector2(128, 128))
		var shooter: int = arena.add_unit(cannon_type, Vector2(512, 512), 0)
		var victim: int = arena.add_unit("armflash", Vector2(640, 512), 0)
		arena.units[shooter].team = 1
		var firing = Combat.new(arena)
		firing.gravity = 4369
		var health: int = arena.units[victim].health
		firing.attack(shooter, victim)
		for step in range(300):
			arena.step()
			firing.step()
			if not arena.units.has(victim):
				break
		var damaged: bool = not arena.units.has(victim) or arena.units[victim].health < health
		checks.append(damaged)
		if not damaged:
			printerr("Elevated cannon target missed: ", elevation, " shots=", firing.shots_fired)
	var weapon: Dictionary = catalog.weapon(str(catalog.definition(cannon_type).weapon1)).definition
	var starts := sound_events.filter(func(event: Dictionary) -> bool: return event.name == str(weapon.soundstart))
	var impacts := sound_events.filter(func(event: Dictionary) -> bool: return event.name == str(weapon.soundhit))
	checks.append(starts.size() == combat.shots_fired and not starts.is_empty())
	checks.append(not impacts.is_empty())
	var failures := checks.count(false)
	print("CANNON_COMBAT %d / %d checks pass; shots=%d hits=%d" % [checks.size() - failures, checks.size(), combat.shots_fired, combat.hits])
	quit(0 if failures == 0 else 1)
