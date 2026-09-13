extends RefCounted
const Ground = preload("res://ground_motion.gd")
## Isolated projectile burst transition; sound/spread/pool consolidation excluded.
static func advance(source: Dictionary, tick: int, interval: int, timer: int, speed: int, distance: int, fresh: Array) -> Dictionary:
	var result := {"source": source.duplicate(true), "copy": null, "refresh": false}
	var state: Dictionary = result.source
	interval &= 65535
	var due: int = (int(state.timestamp) + interval) & 0xffffffff
	if int(state.remaining) == 0 or due > (tick & 0xffffffff):
		return result
	result.refresh = interval > 4 or (int(state.remaining) & 1) != 0
	if result.refresh:
		state.position = fresh.duplicate()
	state.remaining = (int(state.remaining) - 1) & 65535
	state.timestamp = due
	var projectile: Dictionary = state.duplicate(true)
	projectile.timestamp = tick & 0xffffffff
	var duration := timer & 65535
	if duration == 0:
		assert(speed > 0)
		@warning_ignore("integer_division")
		duration = ((distance + 0x100000) & 0xffffffff) / speed
	projectile.deadline = (tick + duration) & 0xffffffff
	projectile.remaining = 0
	result.copy = projectile
	if int(state.remaining) == 0:
		state.removed = true
	return result

static func apply_spread(source: Dictionary, speed: int, spray: int, random_value: int) -> void:
	if (spray & 65535) == 0:
		return
	var trig := Ground.new()
	var heading: int = (int(source.heading) - ((spray & 65535) >> 1) + random_value) & 65535
	var horizontal := trig.velocity_component(int(source.pitch), speed, 16384)
	source.velocity[0] = Ground.signed32(-trig.velocity_component(heading, horizontal, 0))
	source.velocity[2] = Ground.signed32(-trig.velocity_component(heading, horizontal, 16384))
