extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var world := World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	world.remove_unit(world.builder_id)
	world.energy = 0
	world.configure_wind(500, 501)
	var generator := world.add_unit("armwin", Vector2(512, 512), 0)
	var combat := Combat.new(world)
	var checks: Array = [combat.burst_random == world.game_random]
	world.step()
	checks.append(world.wind_state.changed == 0 and world.energy == 0)
	world.step()
	checks.append(world.wind_state.changed == 1 and world.wind_state.strength == 500)
	for tick in range(29):
		world.step()
	checks.append(is_equal_approx(world.energy, 3.0) and world.scripts[generator].fault.is_empty())
	checks.append(world.set_active(generator, false))
	var energy: float = world.energy
	for tick in range(30):
		world.step()
	checks.append(world.energy == energy)
	world.set_active(generator, true)
	for tick in range(30):
		world.step()
	checks.append(world.energy > energy and world.scripts[generator].fault.is_empty())
	print("LIVE_WIND %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
