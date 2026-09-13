extends RefCounted
## 0x43e0b0: consumes already transformed runtime vertices, not raw 3DO vertices.
const Ground = preload("res://ground_motion.gd")
const Origin = preload("res://piece_origin.gd")

static func transform_vertex(pieces: Array, target: int, vertex: Array, angles: Array) -> Array:
	var point := vertex.duplicate()
	while target >= 0:
		var piece: Dictionary = pieces[target]
		var rotation: Array = piece.rotation.duplicate()
		if int(piece.parent) < 0:
			rotation[0] = int(rotation[0]) + int(angles[2])
			rotation[1] = int(rotation[1]) + int(angles[1])
			rotation[2] = int(rotation[2]) + int(angles[0])
		point = Origin.rotate(point, rotation)
		for axis in range(3):
			point[axis] = Ground.signed32(int(point[axis]) + int(piece.offset[axis]) + int(piece.move[axis]))
		target = int(piece.parent)
	return point

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
