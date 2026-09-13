extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Float = preload("res://upkeep_gate.gd")
func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var world := World.new(catalog, Navigation.new(64, 64, heights), Vector2(512, 512))
	world.remove_unit(world.builder_id)
	world.energy = 0
	world.metal = 0
	var metal := heights.duplicate()
	for z in [7, 8, 9]:
		for x in [7, 8, 9]:
			metal[z * 64 + x] = 223
	var checks: Array = [not world.set_terrain_metal(PackedByteArray([1])), world.set_terrain_metal(metal)]
	# Half-cell position distinguishes original +8 rounding from truncation.
	var extractor := world.add_unit("armmex", Vector2(128, 128), 0)
	var unfinished := world.add_unit("armmex", Vector2(320, 320), 1)
	var yield_value := Float.float32(2016.0 * Float.float32(0.001))
	checks.append(world.units[extractor].extractor_yield == yield_value)
	world.step()
	checks.append(world.metal == yield_value and world.units[extractor].energy_ledger.debt == 3.0)
	for tick in range(30):
		world.step()
	checks.append(world.metal == yield_value and world.units[unfinished].energy_ledger.debt == 0.0)
	world.add_unit("armsolar", Vector2(640, 640), 0)
	for tick in range(30):
		world.step()
	checks.append(world.metal == yield_value and world.units[extractor].energy_ledger.debt == 0.0)
	for tick in range(30):
		world.step()
	checks.append(world.metal == Float.float32(yield_value * 2))
	checks.append(world.set_active(extractor, false) and not world.set_active(unfinished, false))
	var balance: float = world.metal
	for tick in range(30):
		world.step()
	checks.append(world.metal == balance)
	checks.append(world.set_active(extractor, true))
	for tick in range(30):
		world.step()
	checks.append(world.metal > balance and world.scripts[extractor].fault.is_empty())
	print("LIVE_EXTRACTOR %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
