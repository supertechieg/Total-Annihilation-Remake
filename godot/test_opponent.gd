extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const Opponent = preload("res://opponent.gd")
func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var factory: int = world.add_unit("armvp", Vector2(512, 512), 0, 1)
	world.add_unit("armsolar", Vector2(800, 512), 0, 1)
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
		world.factories[factory].queue.size() <= 1]
	for unit: Dictionary in world.units.values():
		if unit.type == "armflash":
			checks.append(int(unit.team) == 1)
	var replacements := 0
	for unit: Dictionary in world.units.values():
		if unit.type == "armcv" and world.can_build(int(unit.id)):
			replacements += 1
	checks.append(replacements == 1)
	world.remove_unit(factory)
	var queued := opponent.queued
	for tick in range(60):
		world.step()
		opponent.step()
		combat.step()
	checks.append(opponent.queued == queued)
	print("OPPONENT %d / %d checks pass; queued=%d attacks=%d" % [checks.size() - checks.count(false), checks.size(), opponent.queued, opponent.attacks])
	quit(0 if checks.count(false) == 0 else 1)
