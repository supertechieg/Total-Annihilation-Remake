extends RefCounted
## Original 0x49b720 line-of-sight branch for beam weapons (flag 0x8). See analysis/BEAM_WEAPONS.md.
const Ground = preload("res://ground_motion.gd")

static func advance(input: Dictionary) -> Dictionary:
	var head: Array = input.head.duplicate()
	var tail: Array = input.tail.duplicate()
	var released := bool(input.released)
	var tick := int(input.tick) & 0xffffffff
	# Expiration precedes movement and marks the round removed without moving it.
	if tick >= (int(input.deadline) & 0xffffffff):
		return {"head": head, "tail": tail, "released": released, "removed": true}
	for axis in range(3):
		head[axis] = Ground.signed32(int(head[axis]) + int(input.velocity[axis]))
	if bool(input.beam):
		if released:
			for axis in range(3):
				tail[axis] = Ground.signed32(int(tail[axis]) + int(input.velocity[axis]))
		# The tail only starts on the following update once launch + duration is strictly earlier.
		elif ((int(input.launch) + (int(input.duration) & 0xffff)) & 0xffffffff) < tick:
			released = true
	return {"head": head, "tail": tail, "released": released, "removed": false}
