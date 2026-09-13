extends RefCounted
## Provisional footprint-aware terrain A*. Not the original TA pathfinder.
const CELL := 16
const Limits = preload("res://terrain_limits.gd")
const Heights = preload("res://terrain_heights.gd")
const Footprint = preload("res://footprint_passability.gd")
const DIRECTIONS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
var width: int
var height: int
var heights: PackedByteArray
var blocked := PackedByteArray()
var terrain_clearance := PackedByteArray()
var sea_level := 0
var last_expanded := 0
var failure := ""

func _init(w: int, h: int, data: PackedByteArray, sea := 0, slope := 20, depth := 35, footprint := Vector2i(2, 2), minimum_depth := -10000, water_slope := -1) -> void:
	width = w
	height = h
	heights = data
	sea_level = sea
	assert(width > 0 and height > 0 and heights.size() == width * height)
	blocked.resize(width * height)
	var extrema := Heights.prepare(heights, width, height)
	var cell_blocked := PackedByteArray()
	cell_blocked.resize(width * height)
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			# Last row/column have no complete terrain quad.
			cell_blocked[index] = int(x == width - 1 or y == height - 1 or not Limits.passable(extrema.low[index], extrema.high[index], sea_level, depth, minimum_depth, slope, slope if water_slope < 0 else water_slope))
	for index in range(cell_blocked.size()):
		cell_blocked[index] = 1 - cell_blocked[index]
	var map_values := Footprint.prepare(cell_blocked, width, height, footprint)
	terrain_clearance.resize(width * height)
	for y in range(height):
		for x in range(width):
			var origin := Vector2i(x - (footprint.x >> 1), y - (footprint.y >> 1))
			var value := int(map_values[origin.y * width + origin.x]) if inside(origin) else 0
			terrain_clearance[y * width + x] = value
			blocked[y * width + x] = int(value == 0)

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func passable(cell: Vector2i) -> bool:
	return inside(cell) and blocked[cell.y * width + cell.x] == 0

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / CELL), roundi(point.y / CELL))

func height_at(point: Vector2) -> int:
	var cell := cell_at(point).clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
	return heights[cell.y * width + cell.x]

func can_cross(from: Vector2i, to: Vector2i) -> bool:
	if not passable(to):
		return false
	var delta := to - from
	if absi(delta.x) > 1 or absi(delta.y) > 1:
		return false
	if delta.x != 0 and delta.y != 0:
		return passable(from + Vector2i(delta.x, 0)) and passable(from + Vector2i(0, delta.y))
	return true

func nearest_open(point: Vector2) -> Vector2:
	var origin := cell_at(point).clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
	for radius in range(maxi(width, height)):
		for y in range(maxi(0, origin.y - radius), mini(height, origin.y + radius + 1)):
			for x in range(maxi(0, origin.x - radius), mini(width, origin.x + radius + 1)):
				if maxi(absi(x - origin.x), absi(y - origin.y)) == radius and passable(Vector2i(x, y)):
					return Vector2(x * CELL, y * CELL)
	return Vector2(-1, -1)

static func heuristic(a: Vector2i, b: Vector2i) -> int:
	var delta := (a - b).abs()
	return 10 * maxi(delta.x, delta.y) + 4 * mini(delta.x, delta.y)

static func heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if int(heap[parent][0]) <= int(item[0]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

static func heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and int(heap[child + 1][0]) < int(heap[child][0]):
			child += 1
		if int(last[0]) <= int(heap[child][0]):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result

func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	failure = ""
	last_expanded = 0
	var start := cell_at(from)
	var finish := cell_at(to)
	if not passable(start) or not passable(finish):
		failure = "Destination is blocked terrain"
		return PackedVector2Array()
	var costs := PackedInt32Array()
	costs.resize(width * height)
	costs.fill(2147483647)
	var parents := PackedInt32Array()
	parents.resize(width * height)
	parents.fill(-1)
	var first := start.y * width + start.x
	var end := finish.y * width + finish.x
	costs[first] = 0
	var heap: Array = [[heuristic(start, finish), first, 0]]
	while not heap.is_empty():
		var node := heap_pop(heap)
		var index := int(node[1])
		if int(node[2]) != costs[index]:
			continue
		last_expanded += 1
		if index == end:
			var reverse: Array[Vector2i] = []
			while index != -1:
				@warning_ignore("integer_division")
				var cell := Vector2i(index % width, index / width)
				reverse.append(cell)
				index = parents[index]
			reverse.reverse()
			var points := PackedVector2Array([from])
			for i in range(1, reverse.size() - 1):
				if reverse[i] - reverse[i - 1] != reverse[i + 1] - reverse[i]:
					points.append(Vector2(reverse[i] * CELL))
			points.append(Vector2(finish * CELL))
			return points
		@warning_ignore("integer_division")
		var current := Vector2i(index % width, index / width)
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			if not can_cross(current, next):
				continue
			var next_index := next.y * width + next.x
			var cost := costs[index] + (14 if direction.x != 0 and direction.y != 0 else 10)
			if cost < costs[next_index]:
				costs[next_index] = cost
				parents[next_index] = index
				heap_push(heap, [cost + heuristic(next, finish), next_index, cost])
	failure = "No route to destination"
	return PackedVector2Array()
