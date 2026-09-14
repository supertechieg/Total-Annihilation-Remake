extends SceneTree
## Host-only Core Commander construction of Core resource buildings; not full viewer Core faction support.
## Each fixture builds through corcom begin_build, verifies script fault-free completion, then isolates the
## resource building by removing the Commander to assert exact per-settlement production against native-backed math.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Float = preload("res://upkeep_gate.gd")

var failed := false

func fail(label: String) -> void:
	failed = true
	printerr("FAIL " + label)

func build_and_finish(world: RefCounted, type: String, point: Vector2, label: String) -> int:
	var id: int = world.begin_build(type, point)
	if id <= 0:
		fail(label + " begin_build returned 0: " + str(world.status))
		return 0
	for tick in range(6000):
		world.step()
		if world.units[id].remaining == 0.0:
			break
	if world.units[id].remaining != 0.0:
		fail(label + " never completed; remaining=" + str(world.units[id].remaining))
		return 0
	if not world.scripts[id].fault.is_empty():
		fail(label + " script fault: " + world.scripts[id].fault)
		return 0
	return id

func fresh_world(catalog: RefCounted, sea_level: int) -> RefCounted:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	# Commander at (512, 512); building at (576, 512) sits 32px from the commander footprint, inside builddistance 60.
	var world := World.new(catalog, Navigation.new(64, 64, heights, sea_level), Vector2(512, 512), "corcom")
	world.energy = 10000.0
	world.metal = 10000.0
	return world

func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))

	# corsolar: build via corcom, isolate, then verify exact +20 energy per settlement and Deactivate/Activate toggle.
	var world := fresh_world(catalog, 0)
	var solar: int = build_and_finish(world, "corsolar", Vector2(576, 512), "corsolar-build")
	if solar > 0:
		world.remove_unit(world.builder_id)
		world.energy = 0.0
		for tick in range(30):
			world.step()
		if world.energy != 20.0:
			fail("corsolar-active-settle expected 20.0, got " + str(world.energy))
		if not world.set_active(solar, false):
			fail("corsolar-deactivate rejected")
		world.energy = 0.0
		for tick in range(30):
			world.step()
		if world.energy != 0.0:
			fail("corsolar-deactivated still produced " + str(world.energy))
		if not world.set_active(solar, true):
			fail("corsolar-reactivate rejected")
		world.energy = 0.0
		for tick in range(30):
			world.step()
		if world.energy != 20.0:
			fail("corsolar-reactive-settle expected 20.0, got " + str(world.energy))

	# cormakr: build, isolate; deferred maker production yields metal on the first settle then debt blocks a later settle.
	world = fresh_world(catalog, 0)
	var maker: int = build_and_finish(world, "cormakr", Vector2(576, 512), "cormakr-build")
	if maker > 0:
		world.remove_unit(world.builder_id)
		# First settle: debt starts at 0 so the upkeep gate marks the maker productive, producing 1 metal and posting 60 energy debt.
		world.energy = 0.0
		world.metal = 0.0
		for tick in range(30):
			world.step()
		if world.metal != 1.0:
			fail("cormakr-initial-metal expected 1.0, got " + str(world.metal))
		if world.units[maker].energy_ledger.debt <= 0.0:
			fail("cormakr-initial-debt expected positive, got " + str(world.units[maker].energy_ledger.debt))
		# Second settle: debt from prior tick blocks production; no energy supply, so metal must not grow.
		var metal_before: float = world.metal
		for tick in range(30):
			world.step()
		if world.metal != metal_before:
			fail("cormakr-shortage-settle produced " + str(world.metal - metal_before))
		# Recovery: adding energy pays the debt; the settle after debt clears must produce another metal.
		world.energy = 10000.0
		var metal_start: float = world.metal
		for tick in range(90):
			world.step()
		if world.metal <= metal_start:
			fail("cormakr-recovery expected metal growth, got " + str(world.metal - metal_start))
		if not world.scripts[maker].fault.is_empty():
			fail("cormakr-fault " + world.scripts[maker].fault)

	# cormex: build via corcom over a metal-rich footprint, isolate, verify extractor_yield and per-settle metal income.
	world = fresh_world(catalog, 0)
	var metal_grid := PackedByteArray()
	metal_grid.resize(64 * 64)
	# Cover the 3x3 cormex footprint at (576,512) which snaps to cell (36, 32).
	for z in range(30, 36):
		for x in range(34, 40):
			metal_grid[z * 64 + x] = 223
	if not world.set_terrain_metal(metal_grid):
		fail("cormex-set-terrain-metal rejected")
	var extractor: int = build_and_finish(world, "cormex", Vector2(576, 512), "cormex-build")
	if extractor > 0:
		if float(world.units[extractor].get("extractor_yield", 0.0)) <= 0.0:
			fail("cormex-yield non-positive: " + str(world.units[extractor].get("extractor_yield", 0.0)))
		world.remove_unit(world.builder_id)
		world.energy = 10000.0
		world.metal = 0.0
		for tick in range(30):
			world.step()
		var expected_metal: float = Float.float32(world.units[extractor].extractor_yield)
		if not is_equal_approx(world.metal, expected_metal):
			fail("cormex-settle expected " + str(expected_metal) + ", got " + str(world.metal))
		if not world.scripts[extractor].fault.is_empty():
			fail("cormex-fault " + world.scripts[extractor].fault)

	# corwin: build via corcom, isolate, drive wind_state, verify energy grows and script stays fault-free.
	world = fresh_world(catalog, 0)
	world.configure_wind(500, 501)
	var wind: int = build_and_finish(world, "corwin", Vector2(576, 512), "corwin-build")
	if wind > 0:
		world.remove_unit(world.builder_id)
		world.energy = 0.0
		# One step to advance the wind timer once, then another so the strength becomes non-zero (see test_live_wind).
		world.step()
		world.step()
		if int(world.wind_state.get("strength", 0)) != 500:
			fail("corwin-wind-strength expected 500, got " + str(world.wind_state.get("strength", 0)))
		for tick in range(30):
			world.step()
		if world.energy <= 0.0:
			fail("corwin-settle produced no energy: " + str(world.energy))
		if not world.scripts[wind].fault.is_empty():
			fail("corwin-fault " + world.scripts[wind].fault)

	# cortide: build via corcom on water (sea_level 32 keeps depth 32 above the min of 20), isolate, verify tidal income.
	world = fresh_world(catalog, 32)
	world.tidal_strength = 20.0
	var tide: int = build_and_finish(world, "cortide", Vector2(576, 512), "cortide-build")
	if tide > 0:
		world.remove_unit(world.builder_id)
		world.energy = 0.0
		for tick in range(30):
			world.step()
		if world.energy != 20.0:
			fail("cortide-settle expected 20.0, got " + str(world.energy))
		if not world.scripts[tide].fault.is_empty():
			fail("cortide-fault " + world.scripts[tide].fault)

	print("LIVE_CORE_RESOURCES %s" % ("all fixtures pass" if not failed else "FAIL"))
	quit(1 if failed else 0)
