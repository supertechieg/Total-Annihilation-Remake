extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var world := World.new(catalog, Navigation.new(64, 64, heights, 32), Vector2(128, 128))
	world.remove_unit(world.builder_id)
	world.energy = 0
	world.tidal_strength = 20.0
	var generator := world.add_unit("armtide", Vector2(512, 512), 0)
	world.add_unit("armtide", Vector2(640, 640), 1)
	world.step()
	var checks: Array = [world.energy == 20.0, world.set_active(generator, false)]
	for tick in range(30):
		world.step()
	checks.append(world.energy == 20.0)
	world.set_active(generator, true)
	world.tidal_strength = 0.0
	for tick in range(30):
		world.step()
	checks.append(world.energy == 20.0)
	world.tidal_strength = 0.5
	for tick in range(30):
		world.step()
	checks.append(world.energy == 20.5 and world.scripts[generator].fault.is_empty())
	print("LIVE_TIDAL %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
