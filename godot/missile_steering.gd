extends RefCounted
const Direct = preload("res://direct_launch.gd")
const Ground = preload("res://ground_motion.gd")

static func steer(input: Dictionary) -> Dictionary:
	var desired := Direct.solve(input.position, input.target, 0)
	var result := {"heading": int(input.heading), "pitch": int(input.pitch), "accepted": 1}
	for axis in ["heading", "pitch"]:
		var difference := Ground.signed16(int(desired[axis]) - int(result[axis]))
		# Original compares the absolute difference as a signed 16-bit value.
		var magnitude := Ground.signed16(absi(difference))
		if magnitude > 27000 and (int(input.flags) & 0x800000) != 0:
			result.accepted = 0
			return result
		if magnitude < (int(input.turn) & 65535):
			result[axis] = int(desired[axis])
		else:
			result[axis] = (int(result[axis]) + (-int(input.turn) if difference < 0 else int(input.turn))) & 65535
	return result
