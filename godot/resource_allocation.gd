extends RefCounted
const Float = preload("res://upkeep_gate.gd")
static func allocate(available: float, debt: float, accepted: float) -> Dictionary:
	available = Float.float32(available)
	debt = Float.float32(debt)
	accepted = Float.float32(accepted)
	var debt_fraction := Float.float32(available / debt) if available < debt else 1.0
	var left := available - minf(available, debt)
	var accepted_fraction := Float.float32(left / accepted) if left < accepted else 1.0
	return {"remaining": Float.float32(left - minf(left, accepted)), "debt_fraction": debt_fraction, "accepted_fraction": accepted_fraction}
