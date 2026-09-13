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
	world.energy = 0
	world.metal = 0
	world.add_unit("armsolar", Vector2(800, 800), 0, 1)
	world.store_resources(1, {"energy": 0.0, "metal": 0.0, "energy_storage": 1000.0, "metal_storage": 1000.0})
	world.step()
	var checks: Array = [is_equal_approx(float(world.resources(1).energy), 20.0)]
	var commander: Dictionary = catalog.definition("armcom")
	checks.append(is_equal_approx(world.energy, float(commander.get("energymake", "0"))))
	var factory: int = world.add_unit("armvp", Vector2(512, 512), 0, 1)
	var product: int = world.add_unit("armflash", Vector2(512, 512), 1, 1)
	world.energy = 1000
	world.metal = 1000
	world.store_resources(1, {"energy": 0.0, "metal": 0.0, "energy_storage": 1000.0, "metal_storage": 1000.0})
	world.advance_construction(product, factory)
	checks.append(world.units[product].remaining < 1.0 and world.resources(1).energy == 0 and world.energy == 1000 and world.metal == 1000)
	world.settle_economy()
	var unpaid_remaining: float = world.units[product].remaining
	world.advance_construction(product, factory)
	checks.append(world.units[product].remaining == unpaid_remaining and world.units[factory].metal_ledger.debt > 0)
	world.store_resources(1, {"energy": 1000.0, "metal": 1000.0, "energy_storage": 1000.0, "metal_storage": 1000.0})
	world.settle_economy()
	world.advance_construction(product, factory)
	checks.append(world.units[product].remaining < unpaid_remaining and world.resources(1).metal < 1000)
	checks.append(world.energy == 1000 and world.metal == 1000)
	world.remove_unit(product)
	world.queue_unit(factory, "armflash")
	var produced := 0
	for tick in range(120):
		world.step()
		produced = int(world.factories[factory].product)
		if produced != 0:
			break
	checks.append(produced != 0 and int(world.units[produced].team) == 1)
	var hostile: int = world.add_unit("armsolar", Vector2(192, 128), 1, 1)
	var balance: float = world.metal
	checks.append(not world.resume_build(hostile) and world.task_id == 0)
	checks.append(not world.advance_construction(hostile, world.builder_id) and world.units[hostile].remaining == 1.0 and world.metal == balance)
	world.units[hostile].team = 0
	checks.append(world.resume_build(hostile) and world.task_id == hostile)
	print("TEAM_ECONOMY %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
