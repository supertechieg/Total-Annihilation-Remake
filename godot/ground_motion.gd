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

static func distance_squared(a: Array, b: Array) -> int:
	var dx := int(a[0]) - int(b[0])
	var dz := int(a[1]) - int(b[1])
	return ((dx * dx) >> 32) + ((dz * dz) >> 32)

static func distance_raw(a: Array, b: Array) -> int:
	var dx := int(a[0]) - int(b[0])
	var dz := int(a[1]) - int(b[1])
	return int(sqrt(float(dx * dx + dz * dz)))

static func destination_heading(position: Array, target: Array) -> int:
	# Original x87 conversion uses this stored double scale and nearest rounding.
	return roundi(atan2(float(int(position[0]) - int(target[0])), float(int(position[1]) - int(target[1]))) * 10430.37835047) & 65535

func steer(input: Dictionary) -> Dictionary:
	var speed_input: Dictionary = input.duplicate()
	var heading := int(input.heading)
	var turn_step := 0
	speed_input.acceleration = -int(input.brake)
	if not input.waypoints.is_empty():
		var position: Array = input.position
		var previous: Array = input.waypoints[0]
		var target: Array = input.waypoints[1].duplicate()
		var distance := distance_raw(position, target)
		if distance > 0x500000:
			var segment := distance_raw(previous, target)
			if segment >= 65536:
				var pullback := mini(distance - 0x500000, segment)
				for axis in range(2):
					@warning_ignore("integer_division")
					var direction: int = ((int(target[axis]) - int(previous[axis])) << 16) / segment
					target[axis] = int(target[axis]) - ((direction * pullback) >> 16)
		var error := signed16(destination_heading(position, target) - heading)
		turn_step = clampi(error, -int(input.turn_rate), int(input.turn_rate))
		heading = (heading + turn_step) & 65535
		var speed := int(input.speed)
		@warning_ignore("integer_division")
		var turn_distance: int = absi(error) * speed / int(input.turn_rate)
		@warning_ignore("integer_division")
		var stop_distance: int = (((speed * speed) >> 16) << 16) / (int(input.brake) * 2)
		if ((turn_distance * turn_distance) >> 32) * 4 < distance_squared(position, target) and ((stop_distance * stop_distance) >> 32) < distance_squared(position, input.waypoints[2]):
			speed_input.acceleration = input.acceleration
	speed_input.heading = heading
	var result := advance_speed(speed_input)
	result.heading = heading
	result.turn_step = turn_step
	return result

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
