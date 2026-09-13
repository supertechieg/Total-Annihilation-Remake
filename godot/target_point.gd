extends RefCounted
## 0x43e0b0: consumes already transformed runtime vertices, not raw 3DO vertices.
const Ground = preload("res://ground_motion.gd")

static func from_runtime_vertices(vertices: Array, position: Array) -> Array:
	var lower := [0, 0, 0]
	var upper := [0, 0, 0]
	for vertex: Array in vertices:
		for axis in range(3):
			lower[axis] = mini(lower[axis], int(vertex[axis]))
			upper[axis] = maxi(upper[axis], int(vertex[axis]))
	var result: Array = []
	for axis in range(3):
		var total := Ground.signed32(int(lower[axis]) + int(upper[axis]))
		@warning_ignore("integer_division")
		var midpoint := total / 2
		result.append(Ground.signed32(midpoint + int(position[axis])))
	return result
