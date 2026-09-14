extends SceneTree
## Wreck features: placement/removal grid rules, corpse selection, death placement, blocking and projectile collision.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const FeatureWorld = preload("res://feature_world.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var grid := FeatureWorld.new(16, 16, catalog)
	var anchor := grid.place("armflash_dead", 3, 4)
	check(anchor == 4 * 16 + 3, "Wreck anchors at its cell")
	check(grid.codes[anchor] == grid.index_of("armflash_dead") and grid.codes[anchor + 1] == FeatureWorld.CONTINUATION and grid.codes[anchor + 16] == FeatureWorld.CONTINUATION, "2x2 wreck writes anchor and continuation cells")
	check(grid.rows[anchor + 17] == 1 and grid.columns[anchor + 17] == 1 and grid.anchor_of(anchor + 17) == anchor, "Continuations point back to the anchor")
	check(grid.place("armflash_dead", 15, 4) == -1, "Footprints crossing the map edge are rejected")
	check(grid.place("armpw_dead", 4, 5) >= 0 and grid.codes[anchor] == FeatureWorld.NONE, "A new wreck replaces an overlapping destructible wreck")
	var metal := grid.place("moonmetal01", 8, 8)
	check(metal >= 0 and grid.place("armflash_dead", 9, 9) == -1 and grid.codes[metal] != FeatureWorld.NONE, "An indestructible map feature blocks corpse placement")
	check(grid.remove(metal, true), "Forced removal clears indestructible features")
	var heap := grid.place_corpse("armflash_dead", 2, 1, 1, [0, 0, 0], 0)
	check(heap >= 0 and grid.instances[heap].name == "armflash_heap", "Corpse type 2 follows featuredead to the heap")
	check(grid.place_corpse("armflash_dead", 3, 6, 1, [0, 0, 0], 0) == -1, "Corpse type 3 past a heap with no featuredead leaves nothing")
	check(int(grid.instances[heap].metal) == 43 and int(grid.instances[heap].health) == 500, "Instances carry feature metal and damage")
	# Death placement, blocking and projectile collision in a live world.
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(96, 96))
	var combat = Combat.new(world)
	var victim: int = world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
	world.collision.sync(world)
	var rect: Rect2i = world.collision.records[victim].rect
	var probe: RefCounted = world.unit_navigation("armflash")
	check(probe.passable(rect.position), "The wreck site is passable before the death")
	combat.apply_damage(victim, int(world.units[victim].health) + 20)
	combat.process_deaths()
	var death: Dictionary = combat.deaths[-1]
	check(int(death.corpsetype) == 1 and int(death.anchor) == rect.position.y * 64 + rect.position.x, "Corpse type 1 places armflash_dead at the unit's collision rectangle cell")
	check(world.features.instances.has(int(death.anchor)) and world.features.instances[int(death.anchor)].name == "armflash_dead", "The wreck instance exists")
	check(not world.navigation.passable(rect.position) or not probe.passable(rect.position), "A blocking wreck blocks ground navigation")
	var shooter_point := [int(death.position_raw[0]), 12 * 65536, int(death.position_raw[2])]
	var shell := {"position_raw": shooter_point, "velocity_raw": [0, 0, 0]}
	check(world.collision.terrain_impact(world, shell, 0), "Projectiles below a wreck's height impact it")
	var above := {"position_raw": [int(death.position_raw[0]), 30 * 65536, int(death.position_raw[2])], "velocity_raw": [0, 0, 0]}
	check(not world.collision.terrain_impact(world, above, 0), "Projectiles above a wreck's height pass")
	world.features.remove(int(death.anchor))
	world.refresh_feature_blocking()
	check(probe.passable(rect.position), "Removing the wreck restores navigation")
	print("WRECKAGE %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
