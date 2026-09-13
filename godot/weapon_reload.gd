extends RefCounted
## Original normal-weapon reload settlement at 0x49e468..0x49e4f2.
const Ground = preload("res://ground_motion.gd")

static func ticks(base: int, health: int, maximum: int, experience: int) -> int:
	assert(maximum > 0)
	@warning_ignore("integer_division")
	var rank: int = mini((experience & 65535) / 5, 5)
	@warning_ignore("integer_division")
	var health_part: int = (Ground.signed16(health) * 20 & 0xffffffff) / maximum
	@warning_ignore("integer_division")
	var experienced: int = ((100 - rank * 6) * (base & 65535)) / 100
	@warning_ignore("integer_division")
	var result: int = Ground.signed32(Ground.signed32(120 - health_part) * experienced) / 100
	return result & 65535
