extends RefCounted
static func float32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_float(0)

static func apply(upkeep: float, debt: float, requested: float, accepted: float) -> Dictionary:
	var productive := float32(debt) <= 0.0
	return {"requested": float32(float32(requested) + float32(upkeep)),
		"accepted": float32(float32(accepted) + float32(upkeep)) if productive else float32(accepted),
		"productive": 1 if productive else 0}
