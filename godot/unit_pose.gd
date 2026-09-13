extends RefCounted
## Matches current viewer transforms; original model/world projection remains unverified.

static func piece_transform(model: Dictionary, poses: Array, name: String) -> Transform3D:
	var by_name: Dictionary = {}
	for pose: Dictionary in poses:
		by_name[str(pose.name).to_lower()] = pose
	var transforms: Array[Transform3D] = []
	for piece: Dictionary in model.pieces:
		var pose: Dictionary = by_name.get(str(piece.name).to_lower(), {})
		var movement: Array = pose.get("position", [0, 0, 0])
		var rotation: Array = pose.get("rotation", [0, 0, 0])
		var offset := Vector3(float(piece.offset[0]) + float(movement[0]), float(piece.offset[1]) + float(movement[1]), -float(piece.offset[2]) - float(movement[2])) / 65536.0
		var angles := Vector3(-float(rotation[0]), -float(rotation[1]), float(rotation[2])) * TAU / 65536.0
		var transform := Transform3D(Basis.from_euler(angles), offset)
		if int(piece.parent) >= 0:
			transform = transforms[int(piece.parent)] * transform
		transforms.append(transform)
		if str(piece.name).to_lower() == name.to_lower():
			return transform
	return Transform3D.IDENTITY
