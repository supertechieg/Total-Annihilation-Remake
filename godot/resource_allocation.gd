extends RefCounted
const Float = preload("res://upkeep_gate.gd")
static func settle(income: float, requested: float, accepted: float, debt: float, debt_fraction: float, accepted_fraction: float) -> Dictionary:
	accepted = Float.float32(accepted)
	debt = Float.float32(debt)
	var unpaid_work := accepted - Float.float32(accepted_fraction) * accepted
	var unpaid_debt := debt - Float.float32(debt_fraction) * debt
	return {"income": 0.0, "requested": 0.0, "accepted": 0.0,
		"debt": Float.float32(unpaid_work + unpaid_debt),
		"previous_income": Float.float32(income), "previous_requested": Float.float32(requested)}

static func allocate(available: float, debt: float, accepted: float) -> Dictionary:
	available = Float.float32(available)
	debt = Float.float32(debt)
	accepted = Float.float32(accepted)
	var debt_fraction := Float.float32(available / debt) if available < debt else 1.0
	var left := available - minf(available, debt)
	var accepted_fraction := Float.float32(left / accepted) if left < accepted else 1.0
	return {"remaining": Float.float32(left - minf(left, accepted)), "debt_fraction": debt_fraction, "accepted_fraction": accepted_fraction}
