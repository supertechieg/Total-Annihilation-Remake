extends RefCounted
const Ground = preload("res://ground_motion.gd")

static func advance(input: Dictionary) -> Dictionary:
	var speed := int(input.speed)
	var velocity: Array = input.velocity.duplicate()
	if (int(input.tick) & 0xffffffff) < (int(input.deadline) & 0xffffffff):
		if speed < int(input.maximum):
			speed = mini((speed + int(input.acceleration)) & 0xffffffff, int(input.maximum))
		var trig := Ground.new()
		var horizontal := trig.velocity_component(int(input.pitch), speed, 16384)
		velocity = [-trig.velocity_component(int(input.heading), horizontal, 0), trig.velocity_component(int(input.pitch), speed, 0), -trig.velocity_component(int(input.heading), horizontal, 16384)]
	else:
		velocity[1] = Ground.signed32(int(velocity[1]) - int(input.gravity))
	var position: Array = []
	for axis in range(3):
		position.append(Ground.signed32(int(input.position[axis]) + int(velocity[axis])))
	return {"position": position, "velocity": velocity, "speed": speed}
