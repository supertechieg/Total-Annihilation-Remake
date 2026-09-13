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
	var builder := world.add_unit("armcv", Vector2(512, 512), 0, 1)
	world.mobile_units[builder] = Mobile.new(world.unit_navigation("armcv"), catalog.definition("armcv"), Vector2(512, 512), world.scripts[builder])
	world.add_unit("armsolar", Vector2(800, 256), 0, 1)
	world.add_unit("armvp", Vector2(512, 256), 0, 1)
	var maker := world.add_unit("armmakr", Vector2(800, 512), 0, 1)
	world.store_resources(1, {"energy": 0.0, "metal": 1000.0, "energy_storage": 1000.0, "metal_storage": 1000.0})
	var opponent := Opponent.new(world, Combat.new(world), 1)
	var debt_seen := false
	var duplicate_pending := false
	var finished := 0
	for tick in range(6000):
		world.step()
		debt_seen = debt_seen or float(world.units[maker].energy_ledger.debt) > 0
		opponent.step()
		var pending := 0
		finished = 0
		for unit: Dictionary in world.units.values():
			if unit.team == 1 and unit.type == "armsolar":
				if float(unit.remaining) > 0:
					pending += 1
				else:
					finished += 1
		duplicate_pending = duplicate_pending or pending > 1
		if finished >= 2:
			break
	var checks: Array = [debt_seen, finished >= 2, not duplicate_pending, opponent.structures_started > 0, world.scripts[builder].fault.is_empty()]
	print("OPPONENT_POWER %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
