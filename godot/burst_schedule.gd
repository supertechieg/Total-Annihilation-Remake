extends RefCounted
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
