extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
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
	for factory_type: String in World.GROUND_FACTORIES:
		for type: String in catalog.build_options(factory_type):
			var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(512, 512), "corcom" if factory_type.begins_with("cor") else "armcom")
			var factory: int = world.add_unit(factory_type, Vector2(640, 512), 0.0)
			world.queue_unit(factory, type)
			for tick in range(5000):
				world.energy = 1000.0
				world.metal = 1000.0
				world.step()
				if not world.completed.is_empty():
					break
			var product: int = world.factories[factory].product
			check(product != 0 and world.mobile_units.has(product), type + " completes and receives movement controller")
			if product == 0 or not world.mobile_units.has(product):
				continue
			check(world.scripts.has(product), type + " executes its original script")
			if not world.scripts.has(product):
				continue
			var vm = world.scripts[product]
			var initial_pose: Array = vm.pieces.duplicate(true)
			for tick in range(25):
				world.step()
			if vm.functions.has("walk"):
				var animated := false
				for piece in range(vm.pieces.size()):
					animated = animated or vm.pieces[piece].position != initial_pose[piece].position or vm.pieces[piece].rotation != initial_pose[piece].rotation
				check(animated, type + " animated pose changes during movement")
			for tick in range(500):
				world.step()
			check(world.factories[factory].product == 0, type + " leaves the factory yard")
			if world.factories[factory].product != 0:
				print(type, " exit: ", world.mobile_units[product].status, " position=", world.units[product].position, " pad=", world.factory_build_position(factory))
			check(world.mobile_units[product].speed == 0, type + " settles after exit order")
			var started := false
			var stopped := false
			for event: Dictionary in vm.events:
				if event.kind == "start":
					started = started or event.function == "StartMoving"
					stopped = stopped or event.function == "StopMoving"
			if vm.functions.has("StartMoving"):
				check(started and stopped, type + " receives movement lifecycle callbacks")
			check(vm.fault.is_empty(), type + " remains fault-free after production and movement: " + vm.fault)
	print("PRODUCED_SCRIPTS %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
