extends RefCounted

@warning_ignore("integer_division")
static func deadline(tick: int, speed: int, weapon_range: int, timer: int, no_auto: bool) -> int:
	var duration := (timer & 65535) if speed == 0 or no_auto else ((weapon_range << 16) & 0xffffffff) / (speed & 0xffffffff)
	return (tick + duration) & 0xffffffff
