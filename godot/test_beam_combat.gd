extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")

func _initialize() -> void:
	var laser_type := "corak"
	for candidate: String in ["armfav", "corfav", "corgator"]:
		if "--" + candidate in OS.get_cmdline_user_args():
			laser_type = candidate
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var weapon: Dictionary = catalog.weapon(str(catalog.definition(laser_type).weapon1))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var shooter: int = world.add_unit(laser_type, Vector2(512, 384), 0)
	var victim: int = world.add_unit("armflash", Vector2(384, 384), 0)
	world.units[shooter].team = 1
	var combat = Combat.new(world)
	combat.gravity = 4369
	var checks := [combat.attack(shooter, victim)]
	var initial_health: int = world.units[victim].health
	var launch_state := {}
	var released_tick := -1
	var sound_events: Array = []
	combat.sound_requested.connect(func(name: String, _position: Vector3) -> void: sound_events.append(name))
	for tick in range(450):
		world.step()
		combat.step()
		for projectile: Dictionary in combat.projectiles:
			if not projectile.get("beam", false):
				continue
			if launch_state.is_empty():
				launch_state = {"launch": int(projectile.launch), "deadline": int(projectile.deadline), "tail": projectile.tail_raw.duplicate(),
					"head": projectile.position_raw.duplicate(), "velocity": projectile.velocity_raw.duplicate(), "released": bool(projectile.released), "tick": combat.tick}
			elif released_tick < 0 and bool(projectile.released) and int(projectile.launch) == int(launch_state.launch):
				released_tick = combat.tick
		if not world.units.has(victim):
			break
	var speed := int(weapon.runtime.velocity_raw_per_tick)
	checks.append(combat.shots_fired > 0 and not launch_state.is_empty())
	# Native 0x49c9c0 deadline: (range << 16) / speed ticks after launch.
	@warning_ignore("integer_division")
	var expected_life := (int(weapon.definition.range) << 16) / speed
	checks.append(not launch_state.is_empty() and int(launch_state.deadline) - int(launch_state.launch) == expected_life)
	# The launch tick moved the head once while the tail stayed at the muzzle; duration 0 releases it one tick later.
	checks.append(not launch_state.is_empty() and not bool(launch_state.released) and launch_state.head != launch_state.tail)
	checks.append(released_tick == int(launch_state.get("launch", -10)) + int(weapon.runtime.duration_ticks) + 1)
	checks.append(not world.units.has(victim) or world.units[victim].health < initial_health)
	checks.append(combat.cycles[shooter].fault.is_empty())
	checks.append(sound_events.has(str(weapon.definition.get("soundstart", ""))))
	var duel = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var a: int = duel.add_unit("armflash", Vector2(384, 384), 0)
	var b: int = duel.add_unit(laser_type, Vector2(512, 384), 0)
	duel.units[b].team = 1
	var battle = Combat.new(duel)
	battle.gravity = 4369
	var a_health: int = duel.units[a].health
	var b_health: int = duel.units[b].health
	checks.append(battle.attack(a, b) and battle.attack(b, a))
	for step in range(1800):
		duel.step()
		battle.step()
		if not duel.units.has(a) or not duel.units.has(b):
			break
	checks.append(not duel.units.has(a) or duel.units[a].health < a_health)
	checks.append(not duel.units.has(b) or duel.units[b].health < b_health)
	checks.append(not duel.units.has(a) or not duel.units.has(b))
	for offset: Vector2 in [Vector2(128, 0), Vector2(-128, 0), Vector2(0, 128), Vector2(0, -128)]:
		var arena = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
		var firer: int = arena.add_unit(laser_type, Vector2(512, 512), 0)
		var target: int = arena.add_unit("armflash", Vector2(512, 512) + offset, 0)
		arena.units[firer].team = 1
		var firing = Combat.new(arena)
		firing.gravity = 4369
		var health: int = arena.units[target].health
		firing.attack(firer, target)
		for step in range(300):
			arena.step()
			firing.step()
			if not arena.units.has(target):
				break
		var damaged: bool = not arena.units.has(target) or arena.units[target].health < health
		checks.append(damaged)
		if not damaged:
			printerr("Beam direction missed: ", offset, " shots=", firing.shots_fired)
	for elevation in [8, 24]:
		var terrain_heights := heights.duplicate()
		for z in range(28, 37):
			for x in range(38, 46):
				terrain_heights[z * 64 + x] = elevation
		var arena = World.new(catalog, Navigation.new(64, 64, terrain_heights), Vector2(128, 128))
		var firer: int = arena.add_unit(laser_type, Vector2(512, 512), 0)
		var target: int = arena.add_unit("armflash", Vector2(640, 512), 0)
		arena.units[firer].team = 1
		var firing = Combat.new(arena)
		firing.gravity = 4369
		var health: int = arena.units[target].health
		firing.attack(firer, target)
		var terrain_blocked := false
		for step in range(300):
			var effects_before: int = firing.effects.size()
			arena.step()
			firing.step()
			terrain_blocked = terrain_blocked or (firing.hits == 0 and firing.effects.size() > effects_before)
			if not arena.units.has(target):
				break
		var damaged: bool = not arena.units.has(target) or arena.units[target].health < health
		if elevation == 24:
			# Under the native lowest-corner test, lower muzzles (Weasel, Instigator) clip the plateau's first cell; see BEAM_WEAPONS.md.
			checks.append(damaged or (firing.shots_fired > 0 and terrain_blocked))
			print("BEAM_ELEVATED_24 %s damaged=%s terrain_blocked=%s" % [laser_type, damaged, terrain_blocked])
		else:
			checks.append(damaged)
			if not damaged:
				printerr("Elevated beam target missed: ", elevation, " shots=", firing.shots_fired)
	var failures := checks.count(false)
	if failures > 0:
		printerr("Beam checks: ", checks, " launch=", launch_state, " released_tick=", released_tick)
	print("BEAM_COMBAT %s %d / %d checks pass; shots=%d hits=%d" % [laser_type, checks.size() - failures, checks.size(), combat.shots_fired, combat.hits])
	quit(0 if failures == 0 else 1)
