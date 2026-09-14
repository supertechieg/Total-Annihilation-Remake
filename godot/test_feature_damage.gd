extends SceneTree
## Feature damage in the live world: accumulation, wreck -> heap -> nothing, radius and flag gates, death blasts and default heights.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const FeatureDamage = preload("res://feature_damage.gd")
const FeatureWorld = preload("res://feature_world.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func blast_at(combat: RefCounted, position_raw: Array, area: int, amount: int, flags := 0) -> void:
	combat.blast({"source": 0, "owner": 1, "position": Vector3(float(position_raw[0]), float(position_raw[1]), float(position_raw[2])) / 65536.0,
		"position_raw": position_raw, "area": area, "edge": 1.0, "explosion": "", "soundhit": "", "damage": {"default": str(amount)}, "collision_flags": flags})

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	check(Combat.GAME_FLAGS & 8 != 0, "Feature damage is enabled by the default game options")
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(96, 96))
	var combat = Combat.new(world)
	var anchor: int = world.features.place("armflash_dead", 30, 30, [488 * 65536, 0, 488 * 65536], 1)
	world.refresh_feature_blocking()
	var probe: RefCounted = world.unit_navigation("armflash")
	check(not probe.passable(Vector2i(30, 30)), "The wreck blocks navigation")
	var centre: Array = world.features.instances[anchor].position_raw
	blast_at(combat, centre, 110, 50)
	check(int(world.features.instances[anchor].damage_taken) == 50 and world.features.instances[anchor].name == "armflash_dead", "A blast adds its default damage to the wreck")
	blast_at(combat, centre, 110, 50, FeatureDamage.UNITS_ONLY)
	check(int(world.features.instances[anchor].damage_taken) == 50, "unitsonly weapons skip features")
	blast_at(combat, [centre[0] + 120 * 65536, 0, centre[2]], 110, 400)
	check(int(world.features.instances[anchor].damage_taken) == 50, "Features beyond half the area of effect are not damaged")
	blast_at(combat, [centre[0] + 40 * 65536, 0, centre[2]], 110, 450)
	check(world.features.instances.has(anchor) and world.features.instances[anchor].name == "armflash_heap", "Reaching the feature damage replaces the wreck with its featuredead heap")
	check(int(world.features.instances[anchor].damage_taken) == 0 and world.features.instances[anchor].position_raw == centre and int(world.features.instances[anchor].owner) == 10, "The heap restarts damage at the wreck position with owner 10")
	check(combat.feature_destructions == 1 and probe.passable(Vector2i(30, 30)), "The non-blocking heap frees navigation")
	blast_at(combat, centre, 48, 30000)
	check(not world.features.instances.has(anchor) and combat.feature_destructions == 2, "Destroying a heap without featuredead leaves nothing")
	# Indestructible and 2D features.
	var metal: int = world.features.place("moonmetal01", 10, 10, null, 10)
	var smudge: int = world.features.place("smudge01", 20, 10)
	blast_at(combat, world.features.instances[metal].position_raw, 200, 30000)
	check(world.features.instances.has(metal) and world.features.instances[metal].name == "moonmetal01", "Indestructible features ignore damage")
	var before: int = combat.feature_destructions
	blast_at(combat, world.features.instances[smudge].position_raw, 40, 1)
	check(world.features.instances.has(smudge) and combat.feature_destructions == before + 1, "A zero-damage 2D smudge is replaced by its own featuredead")
	# A unit's death explosion (BIG_UNITEX: area 110, default 50) damages an adjacent wreck.
	var wreck: int = world.features.place("corraid_dead", 40, 40, [648 * 65536, 0, 648 * 65536], 1)
	var victim: int = world.add_unit("armflash", Vector2(700, 648), 0.0, 1)
	world.collision.sync(world)
	combat.apply_damage(victim, int(world.units[victim].health) + 5)
	combat.process_deaths()
	check(not world.units.has(victim) and int(world.features.instances[wreck].damage_taken) == 50, "A unit's explodeas blast damages an adjacent wreck by its default damage")
	# Default instance positions sit at the 0x485070 terrain height.
	var slope := PackedByteArray()
	slope.resize(16 * 16)
	for z in range(16):
		for x in range(16):
			slope[z * 16 + x] = x * 10
	var grid := FeatureWorld.new(16, 16, catalog)
	grid.heights = slope
	var sloped: int = grid.place("armflash_heap", 3, 3)
	var position: Array = grid.instances[sloped].position_raw
	check(position[0] == 8 * 0x80000 and position[1] == FeatureDamage.height(slope, 16, 16, position[0], position[2]) << 16 and position[1] == 40 << 16, "Default instance height follows the bilinear terrain sample")
	print("FEATURE_DAMAGE %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
