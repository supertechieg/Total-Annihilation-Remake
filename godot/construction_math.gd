extends RefCounted
## Positive build-work primitive, original 0041ba60 and 004011c0.
## Resource settlement and completion lifecycle are separate systems.

static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

static func advance(input: Dictionary) -> Dictionary:
	var remaining := f32(float(input.remaining))
	var health := int(input.health)
	var result := {"accepted": false, "remaining": remaining, "health": health,
		"energy_requested": 0.0, "metal_requested": 0.0, "energy_accepted": 0.0, "metal_accepted": 0.0}
	var work := f32(float(input.work))
	assert(work >= 0 and int(input.build_time) > 0, "Positive construction work and valid build time required")
	if remaining == 0 or work == 0:
		return result
	var next := f32(clampf(remaining - work / float(input.build_time), 0.0, 1.0))
	var progress := f32(remaining - next)
	var energy := f32(f32(float(input.energy_cost)) * progress)
	var metal := f32(f32(float(input.metal_cost)) * progress)
	result.energy_requested = energy
	result.metal_requested = metal
	if float(input.energy_debt) <= 0 and float(input.metal_debt) <= 0:
		result.accepted = true
		result.remaining = next
		result.energy_accepted = energy
		result.metal_accepted = metal
		var added_health := int(remaining * int(input.max_health)) - int(next * int(input.max_health))
		result.health = mini(health + added_health, int(input.max_health))
	return result
