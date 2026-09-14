extends SceneTree
## Weapon death pipeline: severity, Killed corpse type, dying-unit damage immunity, explodeas splash and chains.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func arena(catalog: RefCounted) -> Dictionary:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(96, 96))
	world.step()
	return {"world": world, "combat": Combat.new(world)}

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	# Severity arithmetic fixtures from 0x4864b0.
	check(Combat.death_severity(0, 625, 0) == 1, "Exactly zero health with no prior samples clamps severity to 1")
	check(Combat.death_severity(-625, 625, 100) == 100, "Full overkill plus full prior health gives severity 100")
	check(Combat.death_severity(-100, 1000, 40) == 25, "(-(-100)*100/1000 + 40) / 2 = 25")
	check(Combat.death_severity(-5000, 250, 0) == 100, "Large overkill clamps to 100")
	for case: Array in [[-60, 26, 1], [-300, 40, 2], [-700, 100, 3]]:
		var setup := arena(catalog)
		var world = setup.world
		var combat = setup.combat
		var victim: int = world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
		var neighbour: int = world.add_unit("armflash", Vector2(542, 512), 0.0, 0)
		var distant: int = world.add_unit("armflash", Vector2(512, 712), 0.0, 0)
		world.collision.sync(world)
		world.units[victim].previous_health_percent = int(case[1])
		var neighbour_health: int = world.units[neighbour].health
		combat.apply_damage(victim, int(world.units[victim].health) - int(case[0]))
		check(world.units.has(victim) and combat.pending_deaths.has(victim), "Lethal damage flags the unit dying before processing")
		combat.apply_damage(victim, 10000)
		check(int(world.units[victim].health) == int(case[0]), "A dying unit ignores further damage")
		combat.process_deaths()
		var death: Dictionary = combat.deaths[-1] if not combat.deaths.is_empty() else {}
		var expected_severity := Combat.death_severity(int(case[0]), 625, int(case[1]))
		check(not world.units.has(victim), "Processed death removes the unit")
		check(int(death.get("severity", -1)) == expected_severity, "Death records severity %d" % expected_severity)
		check(int(death.get("corpsetype", -1)) == int(case[2]), "Flash Killed script chooses corpse type %d at severity %d" % [case[2], expected_severity])
		check(str(death.get("corpse", "")) == "armflash_dead", "Death records the definition's corpse feature")
		check(not death.get("debris", []).is_empty(), "Killed EXPLODE debris calls are recorded")
		check(int(world.units[neighbour].health) < neighbour_health, "BIG_UNITEX death explosion damages a unit 30 units away")
		check(int(world.units[distant].health) == int(catalog.definition("armflash").maxdamage), "Death explosion does not reach 200 units")
	# Unfinished units leave no corpse and do not explode.
	var setup := arena(catalog)
	var world = setup.world
	var combat = setup.combat
	var frame: int = world.add_unit("armflash", Vector2(512, 512), 0.5, 1)
	var bystander: int = world.add_unit("armflash", Vector2(540, 512), 0.0, 0)
	world.collision.sync(world)
	var bystander_health: int = world.units[bystander].health
	combat.apply_damage(frame, 5000)
	combat.process_deaths()
	check(int(combat.deaths[-1].corpsetype) == 0, "An unfinished unit leaves no corpse")
	check(int(world.units[bystander].health) == bystander_health, "An unfinished unit does not trigger its death explosion")
	# Chain: a unit killed by another's death explosion is processed in the same step.
	var chain := arena(catalog)
	var first: int = chain.world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
	var second: int = chain.world.add_unit("armpw", Vector2(530, 512), 0.0, 1)
	chain.world.collision.sync(chain.world)
	chain.world.units[second].health = 5
	chain.combat.apply_damage(first, 5000)
	chain.combat.process_deaths()
	check(not chain.world.units.has(first) and not chain.world.units.has(second) and chain.combat.deaths.size() == 2, "Death explosions chain through queued deaths")
	# The 30-tick sampler records previous and current percentages.
	var sampled := arena(catalog)
	var tank: int = sampled.world.add_unit("armflash", Vector2(512, 512), 0.0, 0)
	for tick in range(60):
		sampled.world.step()
	sampled.world.units[tank].health = 300
	for tick in range(30):
		sampled.world.step()
	check(int(sampled.world.units[tank].previous_health_percent) == 100 and int(sampled.world.units[tank].health_percent) == 48, "Health percent samples shift every 30 ticks")
	print("UNIT_DEATH %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
