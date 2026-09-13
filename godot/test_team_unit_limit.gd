extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	world.unit_limit = 2
	var factory: int = world.add_unit("armvp", Vector2(512, 512), 0, 1)
	world.add_unit("armsolar", Vector2(800, 800), 0, 1)
	var checks: Array = [world.team_unit_count(0) == 1, world.team_unit_count(1) == 2]
	var building: int = world.begin_build("armsolar", Vector2(192, 128))
	checks.append(building != 0)
	checks.append(world.placement_error("armsolar", Vector2(64, 128)) == "Unit limit reached")
	world.queue_unit(factory, "armflash")
	for tick in range(120):
		world.step()
	checks.append(world.factories[factory].product == 0 and world.factories[factory].queue.size() == 1)
	var solar := 0
	for unit: Dictionary in world.units.values():
		if unit.type == "armsolar" and int(unit.team) == 1:
			solar = int(unit.id)
	world.remove_unit(solar)
	for tick in range(120):
		world.step()
		if int(world.factories[factory].product) != 0:
			break
	checks.append(world.factories[factory].product != 0 and world.team_unit_count(1) == 2)
	checks.append(world.team_unit_count(0) == 2)
	print("TEAM_UNIT_LIMIT %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
