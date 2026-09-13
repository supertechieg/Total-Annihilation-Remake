extends RefCounted
## Original 0x47de60 terrain branch, after feature/occupancy checks.
static func passable(low: int, high: int, sea: int, maximum: int, minimum: int, slope: int, water_slope: int) -> bool:
	if low < sea - maximum or high > sea - minimum:
		return false
	return ((high - low) & 255) <= (water_slope if low < sea else slope)
