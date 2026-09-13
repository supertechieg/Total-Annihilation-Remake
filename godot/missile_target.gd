extends RefCounted
## Non-cruise target selection. Unit point is its position, not SweetSpot.
static func select(input: Dictionary) -> Dictionary:
	if input.projectile != null:
		return {"source": "projectile", "point": input.projectile.duplicate()}
	if input.unit != null and input.unit_valid:
		return {"source": "unit", "point": input.unit.duplicate()}
	return {"source": "saved", "point": input.saved.duplicate()}
