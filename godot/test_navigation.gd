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

static func feature_grid(width: int, height: int, rects: Array) -> PackedByteArray:
	# Synthetic prepared grids: Comet Catcher places no blocking features.
	var grid := PackedByteArray()
	grid.resize(width * height)
	for rect: Rect2i in rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				grid[y * width + x] = 1
	return grid

func feature_checks() -> void:
	var flat := PackedByteArray()
	flat.resize(32 * 32)
	var plain = Navigation.new(32, 32, flat, 0, 20, 35, Vector2i.ONE)
	var nonblocking = Navigation.new(32, 32, flat, 0, 20, 35, Vector2i.ONE, -10000, -1, feature_grid(32, 32, []))
	check(nonblocking.blocked == plain.blocked and nonblocking.terrain_clearance == plain.terrain_clearance, "Nonblocking feature grid leaves navigation unchanged")
	# A four-by-three blocking feature: every covered cell blocks a single-cell unit.
	var single = Navigation.new(32, 32, flat, 0, 20, 35, Vector2i.ONE, -10000, -1, feature_grid(32, 32, [Rect2i(10, 10, 4, 3)]))
	var covered_blocked := true
	for y in range(10, 13):
		for x in range(10, 14):
			covered_blocked = covered_blocked and not single.passable(Vector2i(x, y)) and single.terrain_clearance[y * 32 + x] == 0
	check(covered_blocked, "Every continuation cell of a multi-cell feature blocks")
	check(single.passable(Vector2i(9, 10)) and single.passable(Vector2i(14, 12)) and single.passable(Vector2i(10, 13)), "Cells beside a multi-cell feature stay open")
	check(single.terrain_clearance[10 * 32 + 9] == 1 and single.terrain_clearance[10 * 32 + 8] == 3, "Feature reduces neighboring clearance like blocked terrain")
	# One blocking cell rejects every three-by-three footprint that covers it.
	var wide = Navigation.new(32, 32, flat, 0, 20, 35, Vector2i(3, 3), -10000, -1, feature_grid(32, 32, [Rect2i(16, 16, 1, 1)]))
	var wide_blocked := true
	for y in range(15, 18):
		for x in range(15, 18):
			wide_blocked = wide_blocked and not wide.passable(Vector2i(x, y))
	check(wide_blocked, "Wide footprint is blocked whenever any covered cell has a blocking feature")
	check(wide.passable(Vector2i(14, 16)) and wide.passable(Vector2i(18, 16)) and wide.passable(Vector2i(16, 14)), "Wide footprint fits beside a single blocking cell")
	check(wide.terrain_clearance[16 * 32 + 14] == 1 and wide.terrain_clearance[16 * 32 + 13] == 3, "Wide footprint clearance border sees the feature")
	# Route around a feature wall with a single opening, using a two-cell-wide unit.
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var walls := [Rect2i(32, 0, 2, 40), Rect2i(32, 47, 2, 17)]
	var nav = Navigation.new(64, 64, heights, 0, 20, 35, Vector2i(2, 2), -10000, -1, feature_grid(64, 64, walls))
	var start := Vector2(128, 128)
	var end := Vector2(800, 128)
	check(Navigation.new(64, 64, heights).path(start, end).size() == 2, "Without features the route is direct")
	var route: PackedVector2Array = nav.path(start, end)
	var through_opening := false
	for p: Vector2 in route:
		through_opening = through_opening or p.y >= 640
	check(route.size() > 2 and through_opening, "Route bends through the opening in a feature wall")
	var unit = Mobile.new(nav, {}, start)
	unit.move_to(end)
	var clear_of_features := true
	for tick in range(3500):
		unit.step()
		var cell: Vector2i = nav.cell_at(unit.point())
		for y in range(cell.y - 1, cell.y + 1):
			for x in range(cell.x - 1, cell.x + 1):
				clear_of_features = clear_of_features and nav.features[y * 64 + x] == 0
	check(clear_of_features, "Moving footprint never covers a blocking feature")
	check(unit.point().distance_to(end) < 3, "Unit follows the route around the feature wall: " + str(unit.point()))
	walls.append(Rect2i(32, 40, 2, 7))
	nav = Navigation.new(64, 64, heights, 0, 20, 35, Vector2i(2, 2), -10000, -1, feature_grid(64, 64, walls))
	check(nav.path(start, end).is_empty(), "Closed feature wall rejects the route")

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
	feature_checks()
	print("NAVIGATION %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
