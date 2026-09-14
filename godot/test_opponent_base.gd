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
	var faction := "core" if "--core" in OS.get_cmdline_user_args() else "arm"
	var roster: Dictionary = Opponent.FACTIONS[faction]
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(128, 128))
	var builder: int = world.add_unit(roster.vehicle_builder, Vector2(512, 512), 0, 1)
	world.mobile_units[builder] = Mobile.new(world.unit_navigation(roster.vehicle_builder), catalog.definition(roster.vehicle_builder), Vector2(512, 512), world.scripts[builder])
	var victim: int = world.add_unit("armstump", Vector2(512, 800), 0, 0)
	var initial: int = world.units[victim].health
	var combat = Combat.new(world)
	var opponent := Opponent.new(world, combat, 1, faction)
	var spent := false
	var interrupted := false
	var interrupted_target := 0
	for tick in range(6500):
		world.step()
		if not interrupted and world.builder_jobs.has(builder):
			var target := int(world.builder_jobs[builder].target)
			if float(world.units[target].remaining) < 0.9:
				interrupted_target = target
				world.stop_build(builder)
				interrupted = true
		opponent.step()
		combat.step()
		spent = spent or float(world.resources(1).metal) < 1000.0
		if not world.units.has(victim) or world.units[victim].health < initial:
			break
	var checks: Array = [opponent.queued > 0, opponent.attacks > 0, spent,
		not world.units.has(victim) or world.units[victim].health < initial,
		opponent.structures_started == 2, interrupted, opponent.structures_resumed == 1,
		world.units.has(interrupted_target) and float(world.units[interrupted_target].remaining) == 0.0]
	var produced := 0
	for unit: Dictionary in world.units.values():
		if unit.type == roster.vehicle_combat:
			produced += 1
			checks.append(int(unit.team) == 1)
	for id: int in world.scripts:
		checks.append(world.scripts[id].fault.is_empty())
	if checks.count(false) > 0:
		printerr("Opponent base checks: ", checks.slice(0, 8), " produced=", produced, " structures=", opponent.structures_started)
	print("OPPONENT_BASE %s %d / %d checks pass; queued=%d attacks=%d" % [faction, checks.size() - checks.count(false), checks.size(), opponent.queued, opponent.attacks])
	quit(0 if checks.count(false) == 0 else 1)
