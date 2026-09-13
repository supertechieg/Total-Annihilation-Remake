extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const Mobile = preload("res://mobile_unit.gd")
const Opponent = preload("res://opponent.gd")
func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var world := World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var metal := heights.duplicate()
	for z in range(43, 46):
		for x in range(43, 46):
			metal[z * 64 + x] = 223
	world.set_terrain_metal(metal)
	var start := Vector2(512, 512)
	var builder := world.add_unit("armcv", start, 0, 1)
	world.mobile_units[builder] = Mobile.new(world.unit_navigation("armcv"), catalog.definition("armcv"), start, world.scripts[builder])
	world.add_unit("armsolar", Vector2(800, 256), 0, 1)
	world.add_unit("armvp", Vector2(512, 256), 0, 1)
	var opponent := Opponent.new(world, Combat.new(world), 1)
	var extractor := 0
	var income := false
	for tick in range(6000):
		world.step()
		opponent.step()
		for id: int in world.units:
			if world.units[id].type == "armmex":
				extractor = id
		if extractor != 0 and float(world.units[extractor].metal_ledger.get("previous_income", 0)) > 0:
			income = true
			break
	var count := 0
	for unit: Dictionary in world.units.values():
		if unit.type == "armmex":
			count += 1
	var checks: Array = [income, count == 1, world.units[builder].position.distance_to(start) > 64, opponent.structures_started == 1]
	if extractor != 0:
		checks.append(world.units[extractor].team == 1 and world.units[extractor].remaining == 0)
		checks.append(world.units[extractor].extractor_yield > 0.009 and world.scripts[extractor].fault.is_empty())
	else:
		checks.append(false)
	print("OPPONENT_EXTRACTOR %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
