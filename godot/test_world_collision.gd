extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")

func occupied(world: RefCounted, id: int) -> int:
	var count := 0
	for cell: Array in world.collision.grid.cells:
		count += int(cell[0] == id)
	return count

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var commander: int = world.builder_id
	var checks := [occupied(world, commander) == 4]
	world.units[commander].position = Vector2(256, 256)
	world.step()
	checks.append(world.collision.records[commander].rect == Rect2i(15, 15, 2, 2))
	checks.append(world.collision.grid.cells[7 * 64 + 7][0] == 0 and occupied(world, commander) == 4)
	var factory: int = world.add_unit("armvp", Vector2(512, 512), 0)
	world.scripts[factory].values[18] = 0
	world.collision.sync(world)
	var closed := occupied(world, factory)
	world.scripts[factory].values[18] = 1
	world.collision.sync(world)
	checks.append(occupied(world, factory) < closed and world.collision.records[factory].yard_open)
	world.scripts[factory].values[18] = 0
	world.collision.sync(world)
	checks.append(occupied(world, factory) == closed)
	world.remove_unit(factory)
	checks.append(not world.collision.records.has(factory) and occupied(world, factory) == 0)
	world.remove_unit(commander)
	checks.append(world.collision.records.is_empty() and occupied(world, commander) == 0)
	var failures := checks.count(false)
	print("WORLD_COLLISION %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
