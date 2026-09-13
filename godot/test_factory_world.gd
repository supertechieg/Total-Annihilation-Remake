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
	for type: String in ["armvp", "armlab"]:
		var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(512, 512))
		var id: int = world.add_unit(type, Vector2(640, 512), 1.0)
		var product_type := "armflash" if type == "armvp" else "armpw"
		check(not world.queue_unit(id, product_type), type + " rejects orders before completion")
		world.units[id].remaining = 0.0
		world.units[id].health = int(catalog.definition(type).maxdamage)
		check(not world.queue_unit(id, "armsolar"), type + " rejects foreign menu unit")
		check(world.queue_unit(id, product_type), type + " accepts original menu unit")
		world.queue_unit(id, product_type)
		world.step()
		check(world.factories[id].product == 0, type + " waits for opening script")
		for tick in range(1200):
			world.step()
			if not world.completed.is_empty():
				break
		var product: int = world.factories[id].product
		check(product > 0, type + " creates a product after opening")
		if product == 0:
			continue
		check(world.units[product].remaining == 0.0, type + " completes original build time")
		check(world.units[product].health == int(catalog.definition(product_type).maxdamage), type + " completed product has full health")
		check(world.factories[id].queue.size() == 1 and world.units.size() == 3, type + " prevents overlapping products")
		check(world.scripts[id].fault.is_empty(), type + " script remains fault-free")
		check(world.units[product].position == world.factory_build_position(id), type + " uses queried build piece")
		world.mobile_units[product].stop()
		for tick in range(20):
			world.step()
		check(world.factories[id].product == product and world.factories[id].queue.size() == 1, type + " stopped product blocks next order")
		check(world.move_unit(product, Vector2(640, 640)), type + " accepts exit movement order")
		for tick in range(500):
			world.energy = 0.0
			world.metal = 0.0
			world.step()
			if world.factories[id].product != product:
				break
		var next_product: int = world.factories[id].product
		check(next_product != product and next_product > 0, type + " begins next item only after pad clears")
		for tick in range(60):
			world.energy = 0
			world.metal = 0
			world.step()
		var unpaid_remaining: float = world.units[next_product].remaining
		world.advance_construction(next_product, id)
		check(world.units[next_product].remaining == unpaid_remaining and world.units[id].metal_ledger.debt > 0, type + " unpaid debt stalls work")
		world.queue_unit(id, product_type)
		world.clear_factory_queue(id)
		check(world.factories[id].queue.is_empty() and world.factories[id].product == next_product, type + " clear pending queue retains current product")
		world.energy = 1000.0
		world.metal = 1000.0
		for tick in range(1200):
			world.step()
		check(world.units[next_product].remaining == 0.0, type + " resumes after resource recovery")
		for tick in range(300):
			world.step()
		check(world.factories[id].product == 0 and world.scripts[id].values.get(5) == 0, type + " closes when production is finished")
		world.unit_limit = world.units.size()
		world.queue_unit(id, product_type)
		for tick in range(200):
			world.step()
		check(world.factories[id].product == 0 and world.factories[id].queue.size() == 1, type + " capacity stalls without losing queue")
	print("FACTORY_WORLD %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
