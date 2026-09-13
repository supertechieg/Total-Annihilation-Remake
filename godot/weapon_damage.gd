extends RefCounted
const Ground = preload("res://ground_motion.gd")

static func base_damage(definition: Dictionary, unit_type: String) -> int:
	return Ground.signed32(int(definition[unit_type])) if definition.has(unit_type) else int(definition.get("default", "0")) & 65535

static func amount(base: int, multiplier: float, experience := 0, flags := 0, has_source := true) -> int:
	var encoded := PackedByteArray()
	encoded.resize(4)
	encoded.encode_float(0, multiplier)
	var damage := Ground.signed32(int(float(base) * encoded.decode_float(0)))
	if has_source:
		@warning_ignore("integer_division")
		var bonus: int = mini((experience & 65535) / 5, 5) * 6 + 100
		@warning_ignore("integer_division")
		damage = Ground.signed32(damage * bonus) / 100
	if (flags & 0x80) != 0:
		damage = Ground.signed32(damage * 2)
	if (flags & 0x100) != 0:
		@warning_ignore("integer_division")
		damage = damage / 2
	return damage
