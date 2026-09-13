extends SceneTree
const Navigation = preload("res://terrain_navigation.gd")
const Mobile = preload("res://mobile_unit.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var nav = Navigation.new(64, 64, heights)
	check(nav.terrain_clearance[8 * 64 + 8] == 3, "Open terrain retains full clearance")
	check(nav.terrain_clearance[1 * 64 + 1] == 1, "Fitting footprint at boundary retains limited clearance")
	var unit = Mobile.new(nav, {}, Vector2(128, 128))
	check(unit.move_to(Vector2(512, 128)), "Accept reachable destination")
	var started := false
	var stopped := false
	for tick in range(1600):
		unit.step()
		started = started or "StartMoving" in unit.callbacks
		stopped = stopped or "StopMoving" in unit.callbacks
	check(unit.point().distance_to(Vector2(512, 128)) < 3, "Arrive without teleportation or oscillation: " + str(unit.point()))
	check(unit.speed == 0 and unit.route.is_empty(), "Arrival brakes to rest")
	check(started and stopped, "Real movement emits start and stop callbacks")
	unit.move_to(Vector2(512, 512))
	for tick in range(80):
		unit.step()
	var before_stop: Vector2 = unit.point()
	unit.stop()
	for tick in range(10):
		unit.step()
	check(unit.speed == 0 and unit.point().distance_to(before_stop) < 4, "Stop order brakes within short distance")
	# A high wall with one gap: all paths and simulated steps must respect clearance.
	for y in range(64):
		if y < 40 or y > 46:
			heights[y * 64 + 32] = 100
	nav = Navigation.new(64, 64, heights)
	var start := Vector2(128, 128)
	var end := Vector2(800, 128)
	var route: PackedVector2Array = nav.path(start, end)
	check(not route.is_empty() and route.size() > 2, "Route bends through wall opening")
	var through_gap := false
	for p: Vector2 in route:
		through_gap = through_gap or p.y >= 640
	check(through_gap, "Route uses the opening")
	unit = Mobile.new(nav, {}, start)
	unit.move_to(end)
	var valid_steps := true
	for tick in range(3500):
		unit.step()
		valid_steps = valid_steps and nav.passable(nav.cell_at(unit.point()))
	check(valid_steps, "Movement never enters blocked terrain")
	check(unit.point().distance_to(end) < 3, "Follow route around wall: " + str(unit.point()) + " " + unit.status)
	for y in range(64):
		heights[y * 64 + 32] = 100
	nav = Navigation.new(64, 64, heights)
	check(nav.path(start, end).is_empty(), "Fully closed barrier rejects path")
	check(nav.path(start, Vector2(-1, -1)).is_empty(), "Map boundary destination rejected")
	var tiny := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0])
	nav = Navigation.new(3, 3, tiny, 0, 20, 35, Vector2i.ONE)
	nav.blocked[1] = 1
	nav.blocked[3] = 1
	check(nav.path(Vector2.ZERO, Vector2(16, 16)).is_empty(), "Diagonal cannot cut a blocked corner")
	var ramp := PackedByteArray()
	ramp.resize(16 * 16)
	for y in range(16):
		for x in range(16):
			ramp[y * 16 + x] = x * 10
	nav = Navigation.new(16, 16, ramp, 0, 12, 35, Vector2i(3, 3))
	check(nav.passable(Vector2i(8, 8)), "Wide unit accepts gradual ramp with legal individual slopes")
	check(not nav.path(Vector2(48, 128), Vector2(192, 128)).is_empty(), "Wide unit can route along gradual ramp")
	ramp[8 * 16 + 8] = 200
	nav = Navigation.new(16, 16, ramp, 0, 12, 35, Vector2i(3, 3))
	check(not nav.passable(Vector2i(8, 8)), "Sharp local rise blocks wide footprint")
	print("NAVIGATION %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
