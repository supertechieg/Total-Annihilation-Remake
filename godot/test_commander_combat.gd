extends SceneTree
## Commander primary beam laser through an externally stepped script and movement controller, as the viewer runs it.
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

func arena(catalog: RefCounted, commander: String, enemy_offset: Vector2) -> Dictionary:
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
	var enemy: int = world.add_unit("corraid" if commander == "armcom" else "armflash", start + enemy_offset, 0, 1)
	return {"world": world, "vm": vm, "mobile": mobile, "combat": combat, "enemy": enemy}

func run(setup: Dictionary, ticks: int) -> void:
	var world = setup.world
	for tick in range(ticks):
		# Viewer order: external script and movement first, then world and combat.
		setup.vm.step()
		setup.mobile.step()
		world.units[world.builder_id].position = setup.mobile.point()
		world.step()
		setup.combat.step()
		if not world.units.has(setup.enemy):
			break

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	for commander: String in ["armcom", "corcom"]:
		# Holding guard: engages an enemy inside weapon range without moving.
		var hold := arena(catalog, commander, Vector2(160, 0))
		var world = hold.world
		var enemy_health: int = world.units[hold.enemy].health
		check(hold.combat.enable_guard(world.builder_id, false), commander + " accepts a holding guard")
		check(world.units[world.builder_id].has("weapon_launch_offset"), commander + " captures its weapon launch offset")
		var start: Vector2 = hold.mobile.point()
		run(hold, 1200)
		check(hold.combat.shots_fired > 0, commander + " holding guard fires its laser")
		check(not world.units.has(hold.enemy) or int(world.units[hold.enemy].health) < enemy_health, commander + " damages an in-range enemy")
		check(hold.mobile.point() == start, commander + " holding guard does not move")
		check(hold.vm.fault.is_empty(), commander + " script remains fault-free")
		# Out of weapon range: a holding guard ignores it.
		var far := arena(catalog, commander, Vector2(280, 0))
		far.combat.enable_guard(far.world.builder_id, false)
		run(far, 300)
		check(far.combat.shots_fired == 0 and far.mobile.point() == Vector2(512, 512), commander + " holding guard ignores enemies beyond weapon range")
		# Explicit pursuit order: closes distance, then fires.
		check(far.combat.attack(far.world.builder_id, far.enemy, true), commander + " accepts a pursuit attack order")
		var far_health: int = far.world.units[far.enemy].health
		run(far, 1500)
		check(far.mobile.point().distance_to(Vector2(512, 512)) > 16, commander + " pursuit moves toward the target")
		check(not far.world.units.has(far.enemy) or int(far.world.units[far.enemy].health) < far_health, commander + " pursuit damages the target")
		check(far.vm.fault.is_empty(), commander + " script remains fault-free after pursuit")
		# Enemy units target the Commander's SweetSpot through its attached script.
		var hunted := arena(catalog, commander, Vector2(150, 0))
		var commander_health: int = hunted.world.units[hunted.world.builder_id].health
		hunted.combat.attack(hunted.enemy, hunted.world.builder_id)
		run(hunted, 900)
		check(int(hunted.world.units[hunted.world.builder_id].health) < commander_health, commander + " can be damaged by an enemy")
	print("COMMANDER_COMBAT %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
