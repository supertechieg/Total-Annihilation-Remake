extends RefCounted
const Float = preload("res://upkeep_gate.gd")

static func accumulate(income: float, active: bool, extracts: float, makes: int, wind: float, tidal: float, wind_strength: float, tidal_strength: float) -> float:
	income = Float.float32(income)
	if not active or Float.float32(extracts) > 0 or (makes & 255) != 0:
		return income
	if Float.float32(wind) > 0:
		return Float.float32(income + Float.float32(wind) * Float.float32(wind_strength))
	if Float.float32(tidal) > 0:
		return Float.float32(income + Float.float32(tidal) * Float.float32(tidal_strength))
	return income
