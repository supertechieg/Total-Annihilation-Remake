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
	var raider: int = world.add_unit("armrock", Vector2(512, 384), 0)
	var flash: int = world.add_unit("armflash", Vector2(384, 384), 0)
	world.units[raider].team = 1
	var combat = Combat.new(world)
	combat.gravity = 4369
	var checks := [combat.attack(raider, flash)]
	var initial_health: int = world.units[flash].health
	var airborne := false
	for tick in range(450):
		world.step()
		combat.step()
		for projectile: Dictionary in combat.projectiles:
			airborne = airborne or projectile.get("rocket", false)
		if not world.units.has(flash):
			break
	checks.append(combat.shots_fired > 0 and airborne)
	checks.append(not world.units.has(flash) or world.units[flash].health < initial_health)
	checks.append(combat.cycles[raider].fault.is_empty())
	var duel = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var a: int = duel.add_unit("armflash", Vector2(384, 384), 0)
	var b: int = duel.add_unit("armrock", Vector2(512, 384), 0)
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
		var shooter: int = arena.add_unit("armrock", Vector2(512, 512), 0)
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
			printerr("Rocket direction missed: ", offset, " shots=", firing.shots_fired)
	for elevation in [8, 24]:
		var terrain_heights := heights.duplicate()
		for z in range(28, 37):
			for x in range(38, 46):
				terrain_heights[z * 64 + x] = elevation
		var arena = World.new(catalog, Navigation.new(64, 64, terrain_heights), Vector2(128, 128))
		var shooter: int = arena.add_unit("armrock", Vector2(512, 512), 0)
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
			printerr("Elevated rocket target missed: ", elevation, " shots=", firing.shots_fired)
	# A spent motor must transition to falling, not expire like an EMG round.
	var spent := {"source": -1, "owner": 0, "position": Vector3(700, 100, 700), "previous": Vector3(700, 100, 700),
		"position_raw": [700 * 65536, 100 * 65536, 700 * 65536], "velocity_raw": [65536, 0, 0],
		"speed": 65536, "maximum": 65536, "acceleration": 8738, "heading": 49152, "pitch": 0,
		"deadline": combat.tick, "area": 48, "edge": 0.0, "damage": {"default": "105"}}
	checks.append(combat.step_rocket(spent))
	checks.append(int(spent.velocity_raw[1]) == -4369 and spent.position.y < 100.0)
	var failures := checks.count(false)
	print("ROCKET_COMBAT %d / %d checks pass; shots=%d hits=%d" % [checks.size() - failures, checks.size(), combat.shots_fired, combat.hits])
	quit(0 if failures == 0 else 1)
