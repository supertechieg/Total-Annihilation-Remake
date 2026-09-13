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
	for z in range(19, 22):
		for x in range(19, 22):
			metal[z * 64 + x] = 223
	world.set_terrain_metal(metal)
	world.add_unit("armmex", Vector2(320, 320), 0, 1)
	world.store_resources(1, {"energy": 1000.0, "metal": 50.0, "energy_storage": 1000.0, "metal_storage": 1000.0})
	var start := Vector2(512, 512)
	var builder := world.add_unit("armcv", start, 0, 1)
	world.mobile_units[builder] = Mobile.new(world.unit_navigation("armcv"), catalog.definition("armcv"), start, world.scripts[builder])
	for x in [640, 704, 768, 832]:
		world.add_unit("armsolar", Vector2(x, 128), 0, 1)
	world.add_unit("armvp", Vector2(512, 256), 0, 1)
	var opponent := Opponent.new(world, Combat.new(world), 1)
	var extractor := 0
	var income := false
	var debt_seen := false
	for tick in range(18000):
		world.step()
		opponent.step()
		for unit: Dictionary in world.units.values():
			if unit.team == 1:
				debt_seen = debt_seen or float(unit.metal_ledger.debt) > 0
		for id: int in world.units:
			if world.units[id].type == "armmex" and world.units[id].position.distance_to(Vector2(320, 320)) > 100:
				extractor = id
		if extractor != 0 and float(world.units[extractor].metal_ledger.get("previous_income", 0)) > 0:
			income = true
			break
	var count := 0
	for unit: Dictionary in world.units.values():
		if unit.type == "armmex":
			count += 1
	var checks: Array = [income, count == 2, world.units[builder].position.distance_to(start) > 64, opponent.structures_started >= 1, debt_seen]
	if extractor != 0:
		checks.append(world.units[extractor].team == 1 and world.units[extractor].remaining == 0)
		checks.append(world.units[extractor].extractor_yield > 0.009 and world.scripts[extractor].fault.is_empty())
	else:
		checks.append(false)
	print("OPPONENT_METAL_EXPANSION %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
