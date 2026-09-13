extends RefCounted
## Recovered speed/vector and movement callback primitives, not a navigation system.
## Original routines: 0043cc20, 004b70ef, 004b7123, 0043da70.

const SLOPE_PERCENT := [25, 55, 70, 85, 100, 100, 75, 50, 25, 20, 15]
var sine: Array[int] = []

func _init() -> void:
	# All 512 regenerated entries match the installed executable's table.
	for index in range(512):
		sine.append(roundi(sin(index * TAU / 512.0) * 8192.0))

static func signed16(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

static func signed32(value: int) -> int:
	return ((value + 2147483648) & 4294967295) - 2147483648

func velocity_component(heading: int, speed: int, phase: int) -> int:
	var offset := (((heading & 65535) + phase + 32) >> 6) & 1022
	# The original adds 4096 before arithmetic right shift, including negatives.
	return signed32((sine[offset >> 1] * speed + 4096) >> 13)

func advance_speed(input: Dictionary) -> Dictionary:
	var speed := maxi(0, signed32(int(input.speed) + int(input.acceleration)))
	var slope := clampi(signed16(int(input.pitch)) >> 11, -5, 5)
	@warning_ignore("integer_division")
	var cap: int = SLOPE_PERCENT[slope + 5] * int(input.max_speed) / 100
	if signed16(int(input.height_integer)) < int(input.sea_level) and (int(input.unit_flags) & 0x81000) == 0:
		cap = (cap * 32768) >> 16
	speed = mini(speed, cap)
	return {"speed": speed, "velocity": [
		-velocity_component(int(input.heading), speed, 0), 0,
		-velocity_component(int(input.heading), speed, 16384)]}

static func animation_transition(input: Dictionary) -> Dictionary:
	var rate := 0
	var speed := int(input.speed)
	if (int(input.movement_flags) & 4) == 0 and not bool(input.attached) and (speed != 0 or signed16(int(input.turn_step)) != 0):
		rate = 1
		if int(input.rate1) < speed:
			rate = 3 if int(input.rate2) < speed else 2
	var old_flags := int(input.unit_flags)
	var previous := (old_flags >> 2) & 3
	var callbacks: Array[String] = []
	if rate != previous:
		if rate == 0:
			callbacks.append("StopMoving")
		elif previous == 0:
			callbacks.append("StartMoving")
		if rate > 0:
			callbacks.append("MoveRate%d" % rate)
	return {"unit_flags": ((old_flags & 0xfffffff3) | (rate << 2)), "callbacks": callbacks}
