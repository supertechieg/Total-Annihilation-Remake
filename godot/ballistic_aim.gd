extends RefCounted
## Source-minus-target raw coordinates; output is an unsigned COB angle.
## 0x8000 is the original no-solution sentinel.

static func solve(delta: Array, speed: int, gravity: int, minimum: float) -> int:
	var x := float(delta[0])
	var y := float(delta[1])
	var z := float(delta[2])
	var horizontal := sqrt(x * x + z * z)
	var h2 := horizontal * horizontal
	var v2 := float(speed) * float(speed)
	var distance2 := y * y + h2
	var gravity2 := float(gravity * gravity)
	var discriminant := (y * y * gravity2 + (v2 + 2.0 * float(gravity) * y) * v2) * h2 * h2 - h2 * h2 * gravity2 * distance2
	if discriminant < 0.0 or distance2 == 0.0 or speed <= 0:
		return 0x8000
	var root := sqrt(discriminant)
	var middle := (v2 + float(gravity) * y) * h2
	var first := (middle + root) / (2.0 * distance2)
	var second := (middle - root) / (2.0 * distance2)
	var low := acos(sqrt(first) / float(speed)) if first > 0.0 else 1.570796326794895
	var high := acos(sqrt(second) / float(speed)) if second > 0.0 else 1.570796326794895
	if minimum < low and low <= 0.7853981633974475:
		return int(low * 32768.0 * 0.318309886183791) & 0xffff
	if minimum < high and high <= 0.7853981633974475:
		return int(high * 32768.0 * 0.318309886183791) & 0xffff
	return 0x8000
