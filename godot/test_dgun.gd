extends SceneTree
## Commander D-gun: command fire on weapon slot 3, per-shot energy, noexplode splash along the beam's path.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const Mobile = preload("res://mobile_unit.gd")
const VM = preload("res://cob_vm.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func arena(catalog: RefCounted, commander: String, offsets: Array) -> Dictionary:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var navigation := Navigation.new(64, 64, heights)
	var start := Vector2(512, 512)
	var world = World.new(catalog, navigation, start, commander)
	var vm := VM.new(catalog.load_script(commander))
	vm.read_values = {4: 100, 17: 0}
	vm.invoke("Create")
	var mobile := Mobile.new(navigation, catalog.definition(commander), start, vm)
	world.attach_external(world.builder_id, vm, mobile)
	var combat = Combat.new(world)
	combat.gravity = 4369
	var enemies: Array = []
	for offset: Vector2 in offsets:
		enemies.append(world.add_unit("corraid" if commander == "armcom" else "armflash", start + offset, 0, 1))
	return {"world": world, "vm": vm, "mobile": mobile, "combat": combat, "enemies": enemies}

func tick_once(setup: Dictionary) -> void:
	setup.vm.step()
	setup.mobile.step()
	setup.world.units[setup.world.builder_id].position = setup.mobile.point()
	setup.world.step()
	setup.combat.step()

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	for commander: String in ["armcom", "corcom"]:
		var setup := arena(catalog, commander, [Vector2(0, 110), Vector2(0, 150), Vector2(0, 190)])
		var world = setup.world
		var combat = setup.combat
		check(combat.command_fire(world.builder_id, setup.enemies[0]), commander + " accepts a D-gun command")
		var fired_tick := -1
		var energy_drop := 0.0
		var requested_rise := 0.0
		for tick in range(600):
			var energy_before: float = world.energy
			var requested_before: float = world.units[world.builder_id].energy_ledger.requested
			var shots_before: int = combat.shots_fired
			tick_once(setup)
			if combat.shots_fired > shots_before and fired_tick < 0:
				fired_tick = tick
				energy_drop = energy_before - world.energy
				requested_rise = float(world.units[world.builder_id].energy_ledger.requested) - requested_before
			if fired_tick >= 0 and combat.projectiles.is_empty():
				break
		check(fired_tick >= 0 and combat.shots_fired == 1, commander + " D-gun fires exactly once")
		check(is_equal_approx(energy_drop, 400.0) or energy_drop > 399.0, commander + " D-gun pays 400 energy from stock on its shot (drop %.2f)" % energy_drop)
		check(is_equal_approx(requested_rise, 400.0), commander + " D-gun adds its cost to the Commander's requested energy")
		check(not combat.command_orders.has(world.builder_id), commander + " command order completes after its shot")
		var survivors := 0
		for enemy: int in setup.enemies:
			survivors += int(world.units.has(enemy))
		check(survivors == 0, commander + " noexplode D-gun destroys every enemy along its path (%d survived)" % survivors)
		check(world.units.has(world.builder_id), commander + " survives its own D-gun")
		check(setup.vm.fault.is_empty(), commander + " script remains fault-free after FireTertiary")
		# Insufficient stock: the order waits without firing or paying.
		var poor := arena(catalog, commander, [Vector2(0, 120)])
		poor.world.energy = 100.0
		poor.world.store_resources(0, {"energy": 100.0, "metal": poor.world.metal, "energy_storage": poor.world.energy_storage, "metal_storage": poor.world.metal_storage})
		check(poor.combat.command_fire(poor.world.builder_id, poor.enemies[0]), commander + " accepts a D-gun order without stock")
		for tick in range(60):
			poor.world.energy = 100.0
			tick_once(poor)
		check(poor.combat.shots_fired == 0 and poor.world.units.has(poor.enemies[0]), commander + " D-gun does not fire without 400 energy")
	var plain := arena(catalog, "armcom", [Vector2(0, 120)])
	var tank: int = plain.world.add_unit("armflash", Vector2(700, 700), 0.0)
	check(not plain.combat.command_fire(tank, plain.enemies[0]) and plain.combat.status == "Unit has no command-fire weapon", "Units without a command-fire weapon are rejected")
	print("DGUN %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
