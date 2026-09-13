extends RefCounted

# This gate precedes session/player eligibility checks in the original scheduler.
static func poll(tick: int, deadline: int) -> Dictionary:
	tick &= 0xffffffff
	deadline &= 0xffffffff
	var due := deadline <= tick
	return {"due": due, "deadline": (deadline + 30) & 0xffffffff if due else deadline}
