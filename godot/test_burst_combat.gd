extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var source: int = world.add_unit("armflash", Vector2(384, 384), 0)
	var target: int = world.add_unit("corraid", Vector2(544, 384), 0)
	world.units[target].team = 1
	var combat = Combat.new(world)
	var checks := [combat.attack(source, target)]
	for tick in range(120):
		world.step()
		combat.step()
		if not combat.bursts.is_empty():
			break
	checks.append(combat.bursts.size() == 1 and combat.shots_fired == 0)
	combat.stop(source)
	var emission_ticks: Array = []
	for elapsed in range(1, 11):
		var before: int = combat.shots_fired
		world.step()
		combat.step()
		if combat.shots_fired > before:
			emission_ticks.append(elapsed)
			var projectile: Dictionary = combat.projectiles.back()
			checks.append(projectile.position == projectile.previous)
	checks.append(emission_ticks == [3, 6, 9])
	checks.append(combat.bursts.is_empty() and combat.shots_fired == 3)
	for tick in range(30):
		world.step()
		combat.step()
	checks.append(combat.shots_fired == 3)
	checks.append(world.scripts[source].fault.is_empty())
	combat.attack(source, target)
	for tick in range(120):
		world.step()
		combat.step()
		if not combat.bursts.is_empty():
			break
	var before_death: int = combat.shots_fired
	for tick in range(3):
		world.step()
		combat.step()
	checks.append(combat.shots_fired == before_death + 1)
	world.remove_unit(source)
	world.step()
	combat.step()
	checks.append(combat.bursts.is_empty() and combat.shots_fired == before_death + 1)
	checks.append(not combat.projectiles.is_empty())
	var failures := checks.count(false)
	print("BURST_COMBAT %d / %d checks pass; emission ticks=%s" % [checks.size() - failures, checks.size(), emission_ticks])
	quit(0 if failures == 0 else 1)
