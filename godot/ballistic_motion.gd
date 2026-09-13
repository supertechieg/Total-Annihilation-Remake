extends RefCounted
## Native-compared live shell update. Inputs are signed 16.16 integers.
## Launch aiming, timers and collisions belong to the projectile host.

static func signed32(value: int) -> int:
	return (value & 0xffffffff) - 0x100000000 if (value & 0x80000000) != 0 else value & 0xffffffff

static func integrate(position: Array, velocity: Array, gravity: int, drift: Array) -> Dictionary:
	var next_position: Array = []
	var next_velocity: Array = velocity.duplicate()
	for axis in range(3):
		next_position.append(signed32(int(position[axis]) + int(velocity[axis]) + int(drift[axis])))
	next_velocity[1] = signed32(int(velocity[1]) - gravity)
	return {"position": next_position, "velocity": next_velocity}
