extends SceneTree
## Live-world GET_VALUE 4 feed (0x4807ca) and shared COB RAND: damaged scripted units run SmokeUnit through
## world.game_random and EMIT_SFX; healthy and unfinished units neither smoke nor draw.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const VM = preload("res://cob_vm.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func make_world(catalog: RefCounted) -> RefCounted:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(96, 96))
	world.game_random.game_seed = 0x66e28747
	return world

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var maxdamage := int(catalog.definition("armflash").get("maxdamage", "1"))
	# Healthy finished unit: reads 100, no smoke, no draws.
	var world = make_world(catalog)
	var healthy: int = world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
	check(world.scripts.has(healthy) and world.scripts[healthy].rng == world.game_random, "Scripted units share world.game_random")
	for _i in range(300):
		world.step()
	var vm = world.scripts[healthy]
	check(int(vm.read_values[4]) == 100 and vm.sfx_count == 0 and world.game_random.game_seed == 0x66e28747 and vm.fault.is_empty(),
		"Healthy unit reads 100 and neither smokes nor draws (%d, %d sfx, seed %x)" % [vm.read_values[4], vm.sfx_count, world.game_random.game_seed])
	# Damaged to one third: SmokeUnit emits 257/258 from the live health read and advances the shared seed.
	world = make_world(catalog)
	var damaged: int = world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
	world.units[damaged].health = maxdamage / 3
	for _i in range(300):
		world.step()
	vm = world.scripts[damaged]
	var expected := VM.health_read(maxdamage / 3, maxdamage)
	var kinds := {}
	for event: Array in vm.sfx_events:
		kinds[int(event[2])] = true
	check(int(vm.read_values[4]) == expected and expected < 66, "World feeds GET_VALUE 4 from unit health (%d)" % expected)
	check(vm.sfx_count > 0 and kinds.keys().all(func(kind): return kind == 257 or kind == 258) and vm.fault.is_empty(),
		"Damaged unit emits SmokeUnit SFX (%d events, kinds %s)" % [vm.sfx_count, kinds.keys()])
	check(world.game_random.game_seed != 0x66e28747, "SmokeUnit RAND draws from the shared world RNG")
	# Health changes are picked up on the next tick without recreating the script.
	world.units[damaged].health = maxdamage
	world.step()
	check(int(vm.read_values[4]) == 100, "Health feed refreshes every tick")
	# Unfinished unit: construction health reads low but SmokeUnit waits for completion, so no smoke or draws.
	world = make_world(catalog)
	var frame: int = world.add_unit("armflash", Vector2(512, 512), 0.5, 1)
	for _i in range(300):
		world.step()
	vm = world.scripts[frame]
	check(int(vm.read_values[4]) == VM.health_read(int(world.units[frame].health), maxdamage) and vm.sfx_count == 0 and world.game_random.game_seed == 0x66e28747,
		"Unfinished unit reads construction health without smoking or drawing")
	# QueryBuildInfo dropped with all eight slots busy keeps its initial 0 (0x4b0c40): the pad is piece 0, not "no position".
	world = make_world(catalog)
	var plant: int = world.add_unit("armlab", Vector2(512, 512), 0.0, 1)
	var plant_vm = world.scripts[plant]
	var saved: Array = plant_vm.slots.duplicate()
	for slot in range(plant_vm.slots.size()):
		if plant_vm.slots[slot] == null:
			plant_vm.slots[slot] = {"id": -100 - slot, "name": "busy", "state": "sleep"}
	var drops_before: int = plant_vm.dropped_calls
	var pad: Vector2 = world.factory_build_position(plant)
	plant_vm.slots = saved
	var piece_name: String = plant_vm.pieces[0].name
	var expected_pad := Vector2(INF, INF)
	for piece: Dictionary in catalog.load_unit("armlab").model.pieces:
		if piece.name == piece_name:
			expected_pad = world.units[plant].position + Vector2(float(piece.offset[0]) + float(plant_vm.pieces[0].position[0]), -float(piece.offset[2]) - float(plant_vm.pieces[0].position[2])) / 65536.0
			break
	check(plant_vm.dropped_calls == drops_before + 1 and pad == expected_pad and pad.x != INF,
		"Dropped QueryBuildInfo builds at piece 0 (%s, expected %s)" % [pad, expected_pad])
	print("COB_HEALTH_FEED_CHECKS %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
