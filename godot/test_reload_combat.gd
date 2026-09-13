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
	var source: int = world.add_unit("corraid", Vector2(384, 384), 0)
	var target: int = world.add_unit("armflash", Vector2(512, 384), 0)
	world.units[target].team = 1
	world.units[source].health = 529
	var combat = Combat.new(world)
	combat.gravity = 4369
	var checks := [combat.attack(source, target)]
	for tick in range(200):
		world.step()
		combat.step()
		if combat.shots_fired > 0:
			break
	var cycle = combat.cycles[source]
	checks.append(combat.shots_fired == 1 and cycle.next_burst - cycle.tick == 49)
	var settled: int = cycle.next_burst
	world.units[source].health = 1058
	world.units[source].experience = 25
	world.step()
	combat.step()
	checks.append(cycle.next_burst == settled and combat.shots_fired == 1)
	for tick in range(100):
		world.step()
		combat.step()
		if combat.shots_fired > 1:
			break
	checks.append(combat.shots_fired == 2 and cycle.next_burst - cycle.tick == 31)
	checks.append(cycle.fault.is_empty())
	var failures := checks.count(false)
	print("RELOAD_COMBAT %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
