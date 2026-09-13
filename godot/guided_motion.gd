extends RefCounted
const Rocket = preload("res://rocket_motion.gd")
const Steering = preload("res://missile_steering.gd")

static func advance(input: Dictionary) -> Dictionary:
	var state := input.duplicate(true)
	if (int(state.tick) & 0xffffffff) < (int(state.deadline) & 0xffffffff):
		var angles := Steering.steer({"position": state.position, "target": state.target,
			"heading": state.heading, "pitch": state.pitch, "turn": state.turn, "flags": 0})
		state.heading = angles.heading
		state.pitch = angles.pitch
	var result := Rocket.advance(state)
	result.heading = int(state.heading)
	result.pitch = int(state.pitch)
	return result
