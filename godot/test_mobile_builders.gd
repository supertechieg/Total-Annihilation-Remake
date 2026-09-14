extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const Mobile = preload("res://mobile_unit.gd")
const World = preload("res://construction_world.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	for type: String in ["armcv", "armck", "armmlv", "corcv", "corck", "cormlv"]:
		var core := type.begins_with("cor")
		var prefix := "cor" if core else "arm"
		var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(256, 256), prefix + "com")
		var source: int = world.add_unit(type, Vector2(512, 512), 0.0)
		world.mobile_units[source] = Mobile.new(world.unit_navigation(type), catalog.definition(type), Vector2(512, 512), world.scripts[source])
		var target_type := prefix + ("mine1" if type.ends_with("mlv") else "solar")
		check(world.can_build(source), type + " exposes builder capability")
		check(world.begin_build("armflash" if not core else "corraid", Vector2(576, 512), source) == 0, type + " rejects foreign menu entry")
		if core and not type.ends_with("mlv"):
			check(world.begin_build("corllt", Vector2(576, 512), source) == 0 and world.status == "Not yet verified for Core", type + " rejects unverified Core menu entry")
		check(world.begin_build(target_type, Vector2(800, 512), source) == 0, type + " enforces builder range")
		var point := Vector2(576, 512)
		var target: int = world.begin_build(target_type, point, source)
		check(target > 0, type + " accepts nearby construction")
		if target == 0:
			printerr(world.status)
			continue
		world.step()
		check(world.units[target].remaining == 1.0, type + " waits for construction arm readiness")
		# Stop sampling once work is under way; cormine1's build time finishes within a fixed 250 ticks.
		for tick in range(250):
			world.step()
			if world.units[target].remaining < 0.8:
				break
		var remaining: float = world.units[target].remaining
		check(remaining > 0 and remaining < 1, type + " constructs after original script becomes ready")
		world.stop_build(source)
		for tick in range(60):
			world.step()
		check(world.units[target].remaining == remaining, type + " pause retains paid progress")
		check(world.resume_build(target, source), type + " resumes existing construction")
		var commander_target: int = world.begin_build(prefix + "solar", Vector2(320, 256))
		check(commander_target > 0, type + " Commander can build concurrently")
		for tick in range(1500):
			world.step()
		check(world.units[target].remaining == 0 and world.units[commander_target].remaining == 0, type + " both builders finish independently")
		check(not world.builder_jobs.has(source) and world.scripts[source].values.get(5) == 0, type + " returns to non-building stance")
		check(world.scripts[source].fault.is_empty(), type + " callback lifecycle is fault-free")
		var second: int = world.begin_build(target_type, Vector2(448, 512), source)
		check(second > 0, type + " accepts a second build")
		for tick in range(100):
			world.step()
		var before: float = world.units[second].remaining
		check(world.move_unit(source, Vector2(512, 640)), type + " accepts movement while building")
		for tick in range(300):
			world.step()
		check(not world.builder_jobs.has(source) and world.units[second].remaining == before, type + " movement cancels work without deleting unfinished unit")
		check(not world.resume_build(second, source), type + " distant resume is rejected")
		if core:
			check(world.scripts.has(target) and world.scripts[target].fault.is_empty(), type + " completed Core structure runs its verified script")
	# Completed Core storage raises team capacity through the shared settlement path.
	var storage_world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(256, 256), "corcom")
	var base_energy: float = storage_world.energy_storage
	var base_metal: float = storage_world.metal_storage
	storage_world.add_unit("corestor", Vector2(512, 512), 0.0)
	storage_world.add_unit("cormstor", Vector2(640, 512), 0.0)
	for tick in range(60):
		storage_world.step()
	check(storage_world.energy_storage == base_energy + float(catalog.definition("corestor").energystorage) and storage_world.metal_storage == base_metal + float(catalog.definition("cormstor").metalstorage), "Core storage adds original capacity")
	print("MOBILE_BUILDERS %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
