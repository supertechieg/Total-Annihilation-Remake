extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
var failures := 0
var checks := 0

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
	var navigation = Navigation.new(64, 64, heights)
	var world = World.new(catalog, navigation, Vector2(512, 512))
	check(world.begin_build("armflash", Vector2(576, 512)) == 0, "Reject units outside commander menu")
	check(world.begin_build("armsolar", Vector2(512, 512)) == 0, "Reject footprint overlap")
	check(world.begin_build("armsolar", Vector2(800, 512)) == 0, "Reject out-of-range site")
	var id: int = world.begin_build("armsolar", Vector2(576, 512))
	check(id > 0, "Accept nearby solar collector")
	for tick in range(50):
		world.step()
	check(float(world.units[id].remaining) < 1.0 and float(world.units[id].remaining) > 0, "Construction advances incrementally")
	var remaining: float = world.units[id].remaining
	world.stop_build()
	for tick in range(20):
		world.step()
	check(world.units[id].remaining == remaining, "Stop preserves unfinished structure")
	check(world.resume_build(id), "Resume unfinished structure")
	for tick in range(400):
		world.step()
	check(world.units[id].remaining == 0.0 and world.task_id == 0, "Original build definition reaches completion")
	check(world.units[id].health == int(catalog.definition("armsolar").maxdamage), "Completed structure reaches full health")
	world.energy = 0.0
	for tick in range(30):
		world.step()
	check(is_equal_approx(world.energy, 45.0), "Commander plus solar produce 45 energy per second")
	check(world.scripts[id].fault.is_empty() and world.scripts[id].values.get(20) == 0, "Completed solar opens without VM fault")
	check(world.set_active(id, false), "Completed solar accepts off command")
	world.energy = 0.0
	for tick in range(30):
		world.step()
	check(is_equal_approx(world.energy, 25.0), "Disabled solar stops its energy production")
	for tick in range(70):
		world.step()
	var closed := true
	for piece: Dictionary in world.scripts[id].pieces:
		if str(piece.name).begins_with("dish"):
			closed = closed and piece.rotation == [0, 0, 0]
	check(closed, "All four solar panels reach closed pose")
	var second: int = world.add_unit("armsolar", Vector2(400, 400), 0.0)
	for tick in range(100):
		world.step()
	check(world.scripts[id].values.get(20) == 1 and world.scripts[second].values.get(20) == 0, "Collectors maintain independent activation state")
	world.set_active(id, true)
	for tick in range(100):
		world.step()
	check(world.scripts[id].values.get(20) == 0 and world.scripts[id].fault.is_empty(), "Solar reopens after reactivation")
	check(not world.resume_build(id), "Cannot rebuild completed structure")
	world = World.new(catalog, navigation, Vector2(512, 512))
	id = world.begin_build("armsolar", Vector2(576, 512))
	check(not world.set_active(id, false), "Unfinished structure rejects activation command")
	world.energy = 0.0
	world.metal = 0.0
	world.step()
	check(world.units[id].remaining < 1.0, "Debt-free work is accepted before settlement")
	for tick in range(29):
		world.step()
	world.energy = 0
	world.metal = 0
	world.settle_economy()
	world.resource_deadline = world.ticks + 30
	var debt_remaining: float = world.units[id].remaining
	world.step()
	check(world.units[id].remaining == debt_remaining, "Unpaid debt stalls construction")
	check(world.energy >= 0 and world.metal >= 0, "Resource shortage cannot create negative balances")
	world.energy = 1000
	world.metal = 1000
	world.settle_economy()
	world.step()
	check(world.units[id].remaining < debt_remaining, "Work resumes when resources recover")
	world.unit_limit = world.units.size()
	check(world.begin_build("armsolar", Vector2(464, 512)) == 0, "Configured unit limit is enforced")
	print("CONSTRUCTION_WORLD %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
