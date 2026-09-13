extends RefCounted
## Original origin traversal, distinct from the presentation renderer's matrices.
const Ground = preload("res://ground_motion.gd")

static func model_origin(model: Dictionary, poses: Array, name: String, angles: Array) -> Array:
	var by_name := {}
	for pose: Dictionary in poses:
		by_name[str(pose.name).to_lower()] = pose
	var pieces: Array = []
	var target := -1
	for item: Dictionary in model.pieces:
		var pose: Dictionary = by_name.get(str(item.name).to_lower(), {})
		if str(item.name).to_lower() == name.to_lower():
			target = pieces.size()
		# Original model loader 0x4cb590 reverses X/Z before runtime traversal.
		pieces.append({"parent": item.parent, "offset": [-int(item.offset[0]), int(item.offset[1]), -int(item.offset[2])],
			"move": pose.get("position", [0, 0, 0]), "rotation": pose.get("rotation", [0, 0, 0])})
	return origin(pieces, target, angles)

static func nearest_even(value: float) -> int:
	var lower := floori(value)
	var fraction := value - float(lower)
	return lower + 1 if fraction > 0.5 or (fraction == 0.5 and (lower & 1) != 0) else lower

static func rotate_pair(a: int, b: int, angle: int) -> Array:
	angle = Ground.signed16(angle)
	if angle == 0:
		return [a, b]
	var radians := float(angle) * 9.587379924285e-05
	var cosine := cos(radians)
	var sine := sin(radians)
	return [Ground.signed32(nearest_even(cosine * a - sine * b)), Ground.signed32(nearest_even(sine * a + cosine * b))]

static func rotate(point: Array, rotation: Array) -> Array:
	var xy := rotate_pair(int(point[0]), int(point[1]), int(rotation[2]))
	var yz := rotate_pair(int(xy[1]), int(point[2]), int(rotation[0]))
	var xz := rotate_pair(int(xy[0]), int(yz[1]), int(rotation[1]))
	return [xz[0], yz[0], xz[1]]

static func origin(pieces: Array, target: int, angles: Array) -> Array:
	if target < 0 or target >= pieces.size():
		return [0, 0, 0]
	var piece: Dictionary = pieces[target]
	var point: Array = []
	for axis in range(3):
		point.append(Ground.signed32(int(piece.offset[axis]) + int(piece.move[axis])))
	var parent := int(piece.parent)
	while parent >= 0:
		piece = pieces[parent]
		var rotation: Array = piece.rotation.duplicate()
		if int(piece.parent) < 0:
			rotation[0] = int(rotation[0]) + int(angles[2])
			rotation[1] = int(rotation[1]) + int(angles[1])
			rotation[2] = int(rotation[2]) + int(angles[0])
		point = rotate(point, rotation)
		for axis in range(3):
			point[axis] = Ground.signed32(int(point[axis]) + int(piece.offset[axis]) + int(piece.move[axis]))
		parent = int(piece.parent)
	point[2] = Ground.signed32(-int(point[2]))
	return point
