extends RefCounted
const Ground = preload("res://ground_motion.gd")

static func branch_height(pieces: Array, parent: int) -> int:
	var height := 0
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		if int(piece.parent) != parent:
			continue
		var offset := int(piece.offset[1])
		for vertex: Array in piece.vertices:
			height = maxi(height, Ground.signed32(int(vertex[1]) + offset))
		var has_children := false
		for child: Dictionary in pieces:
			if int(child.parent) == index:
				has_children = true
				break
		if has_children:
			height = maxi(height, Ground.signed32(branch_height(pieces, index) + offset))
	return height

static func from_unit(unit: Dictionary, movement: Dictionary = {}) -> Dictionary:
	var fields: Dictionary = unit.definition if movement.is_empty() else movement
	var x := int(fields.get("footprintx", "0"))
	var z := int(fields.get("footprintz", "0"))
	return {"lower": [-x * 524288, 0, -z * 524288],
		"upper": [x * 524288, branch_height(unit.model.pieces, -1), z * 524288]}
