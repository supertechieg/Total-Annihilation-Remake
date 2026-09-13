extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const Mobile = preload("res://mobile_unit.gd")
const Opponent = preload("res://opponent.gd")
func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var builder: int = world.add_unit("armcv", Vector2(512, 512), 0, 1)
	world.mobile_units[builder] = Mobile.new(world.unit_navigation("armcv"), catalog.definition("armcv"), Vector2(512, 512), world.scripts[builder])
	var victim: int = world.add_unit("armstump", Vector2(512, 800), 0, 0)
	var initial: int = world.units[victim].health
	var combat = Combat.new(world)
	var opponent := Opponent.new(world, combat, 1)
	var spent := false
	for tick in range(6500):
		world.step()
		opponent.step()
		combat.step()
		spent = spent or float(world.resources(1).metal) < 1000.0
		if not world.units.has(victim) or world.units[victim].health < initial:
			break
	var checks: Array = [opponent.queued > 0, opponent.attacks > 0, spent,
		not world.units.has(victim) or world.units[victim].health < initial,
		opponent.structures_started == 2]
	for unit: Dictionary in world.units.values():
		if unit.type == "armflash":
			checks.append(int(unit.team) == 1)
	print("OPPONENT_BASE %d / %d checks pass; queued=%d attacks=%d" % [checks.size() - checks.count(false), checks.size(), opponent.queued, opponent.attacks])
	quit(0 if checks.count(false) == 0 else 1)
