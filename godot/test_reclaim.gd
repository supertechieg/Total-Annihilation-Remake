extends SceneTree
## Reclaim: countdown rule, featurereclamate replacement, builder approach, income credit and cancellation.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const Mobile = preload("res://mobile_unit.gd")
const World = preload("res://construction_world.gd")
const FeatureWorld = preload("res://feature_world.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func flat_world(catalog: RefCounted, commander: String) -> RefCounted:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	return World.new(catalog, Navigation.new(64, 64, heights), Vector2(256, 256), commander)

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	check(World.reclaim_countdown({"metal": 0, "energy": 0}) == 30, "An empty feature counts down 30")
	check(World.reclaim_countdown({"metal": 43, "energy": 0}) == 51, "Countdown truncates 30 + (metal + energy) / 2")
	check(World.reclaim_countdown({"metal": 100, "energy": 250}) == 205, "Energy counts toward the countdown")
	# Replacement grid rules.
	var grid := FeatureWorld.new(16, 16, catalog)
	var wreck := grid.place("armflash_dead", 3, 4, [1, 2, 3], 0)
	check(grid.replace(wreck, true) == wreck and grid.instances[wreck].name == "smudge01", "Reclaiming a wreck leaves its featurereclamate")
	check(grid.instances[wreck].position_raw == [1, 2, 3] and int(grid.instances[wreck].owner) == 10 and grid.codes[wreck + 1] == FeatureWorld.NONE, "The replacement keeps the position, takes owner 10 and its own footprint")
	wreck = grid.place("armflash_dead", 8, 8)
	check(grid.replace(wreck, false) == wreck and grid.instances[wreck].name == "armflash_heap", "Destroying a wreck leaves its featuredead heap")
	check(grid.replace(wreck, false) == -1 and not grid.instances.has(wreck), "A heap without featuredead leaves nothing")
	var flash_dead: Dictionary = catalog.feature("armflash_dead")
	for type: String in ["armcv", "corck"]:
		var prefix := type.substr(0, 3)
		var world = flat_world(catalog, prefix + "com")
		var source: int = world.add_unit(type, Vector2(512, 512), 0.0)
		world.mobile_units[source] = Mobile.new(world.unit_navigation(type), catalog.definition(type), Vector2(512, 512), world.scripts[source])
		var anchor: int = world.features.place("armflash_dead", 44, 31)
		world.refresh_feature_blocking()
		check(not world.unit_navigation(type).passable(Vector2i(44, 31)), type + " wreck blocks navigation before reclaim")
		check(not world.reclaim(source, 5 * 64 + 5) and world.status == "Nothing to reclaim there", type + " rejects an empty cell")
		check(world.reclaim(source, anchor + 65), type + " accepts a wreck through a continuation cell")
		check(world.reclaim_jobs.has(source) and int(world.reclaim_jobs[source].anchor) == anchor and not world.mobile_units[source].route.is_empty(), type + " approaches an out-of-range wreck")
		world.metal = 0.0
		world.energy = 0.0
		var armed := false
		var countdown := 0
		for tick in range(1200):
			world.step()
			if world.reclaim_jobs.has(source) and int(world.reclaim_jobs[source].state) >= 2 and countdown == 0:
				countdown = int(world.reclaim_jobs[source].countdown)
				armed = int(world.scripts[source].values.get(5, 0)) == 1 and world.in_reclaim_range(source, anchor)
			if not world.reclaimed.is_empty():
				break
		check(world.reclaimed.size() == 1, type + " completes the reclaim")
		if world.reclaimed.is_empty():
			printerr(world.reclaim_jobs.get(source, {}))
			continue
		var result: Dictionary = world.reclaimed[0]
		check(armed, type + " works from within build distance with the construction arm ready")
		check(countdown == World.reclaim_countdown(flash_dead), type + " counts down from the feature definition")
		@warning_ignore("integer_division")
		var sleeps := (countdown + 1) / 2
		check(int(result.duration) == 2 * sleeps + 1, type + " finishes after two-tick sleeps subtracting two per run")
		check(world.features.instances.has(anchor) and world.features.instances[anchor].name == "smudge01", type + " wreck becomes smudge01")
		check(world.unit_navigation(type).passable(Vector2i(44, 31)), type + " reclaimed site no longer blocks navigation")
		check(float(world.units[source].metal_ledger.income) == float(flash_dead.metal), type + " credits feature metal to the reclaimer's income")
		var stock: float = world.metal
		for tick in range(40):
			world.step()
			if float(world.units[source].metal_ledger.income) == 0.0:
				break
		check(float(world.units[source].metal_ledger.get("previous_income", -1)) >= float(flash_dead.metal) and world.metal - stock >= float(flash_dead.metal), type + " the next settlement adds reclaimed metal to stock")
		check(not world.reclaim_jobs.has(source) and world.scripts[source].fault.is_empty(), type + " ends the order fault-free")
		check(not world.reclaim(source, anchor) and world.status == "Feature is not reclaimable", type + " rejects the non-reclaimable smudge")
		# Cancellation: a move order and a vanished feature both end the job.
		var second: int = world.features.place("armflash_dead", 30, 31)
		check(world.reclaim(source, second), type + " accepts a second wreck")
		for tick in range(600):
			world.step()
			if world.reclaim_jobs.has(source) and bool(world.reclaim_jobs[source].started):
				break
		check(world.reclaim_jobs.has(source) and bool(world.reclaim_jobs[source].started), type + " starts building stance on the second wreck")
		world.move_unit(source, Vector2(560, 700))
		check(not world.reclaim_jobs.has(source), type + " move order cancels reclaim")
		for tick in range(120):
			world.step()
		check(int(world.scripts[source].values.get(5, 0)) == 0, type + " StopBuilding returns the construction arm")
		check(world.reclaim(source, second), type + " reissues reclaim")
		world.features.remove(second)
		world.step()
		check(not world.reclaim_jobs.has(source) and world.features.instances.size() == 1, type + " job ends when the wreck disappears")
	# Non-reclaimers and the scriptless Commander.
	var world = flat_world(catalog, "armcom")
	var mlv: int = world.add_unit("armmlv", Vector2(512, 512), 0.0)
	world.mobile_units[mlv] = Mobile.new(world.unit_navigation("armmlv"), catalog.definition("armmlv"), Vector2(512, 512), world.scripts[mlv])
	var near: int = world.features.place("armflash_dead", 18, 15)
	check(not world.reclaim(mlv, near), "Minelayers (canreclamate=0) cannot reclaim")
	check(world.reclaim(world.builder_id, near), "The Commander reclaims a wreck in range")
	for tick in range(200):
		world.step()
		if not world.reclaimed.is_empty():
			break
	for tick in range(40):
		world.step()
		if float(world.units[world.builder_id].metal_ledger.income) == 0.0:
			break
	check(world.reclaimed.size() == 1 and float(world.units[world.builder_id].metal_ledger.get("previous_income", 0.0)) >= float(flash_dead.metal), "The Commander's settlement includes reclaimed metal")
	print("RECLAIM %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
