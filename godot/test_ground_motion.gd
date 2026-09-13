extends SceneTree
## Small regression cases confirmed against the native oracle; no game assets required.
const Motion = preload("res://ground_motion.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var motion = Motion.new()
	var input := {"speed": 0, "acceleration": 9830, "max_speed": 78643,
		"pitch": 0, "heading": 0, "height_integer": 0, "sea_level": 0, "unit_flags": 0}
	var result: Dictionary = motion.advance_speed(input)
	check(result.speed == 9830 and result.velocity == [0, 0, -9830], "First acceleration tick and north heading")
	for tick in range(20):
		input.speed = result.speed
		result = motion.advance_speed(input)
	check(result.speed == 78643, "Repeated acceleration saturates at native cap")
	input.speed = result.speed
	input.height_integer = -1
	result = motion.advance_speed(input)
	check(result.speed == 39321, "Underwater cap uses downward integer rounding")
	input.unit_flags = 0x1000
	check(motion.advance_speed(input).speed == 78643, "First water exemption flag")
	input.unit_flags = 0x80000
	check(motion.advance_speed(input).speed == 78643, "Second water exemption flag")
	input.unit_flags = 0
	input.height_integer = 0
	input.pitch = 2048
	check(motion.advance_speed(input).speed == 58982, "Pitch bucket applies 75 percent cap")
	input.pitch = -1
	check(motion.advance_speed(input).speed == 78643, "Negative pitch uses arithmetic shift")
	input.pitch = -32768
	check(motion.advance_speed(input).speed == 19660, "Negative extreme clamps to first slope bucket")
	input.pitch = 32767
	check(motion.advance_speed(input).speed == 11796, "Positive extreme clamps to last slope bucket")
	input.pitch = 0
	input.speed = 100
	input.acceleration = -19660
	check(motion.advance_speed(input).speed == 0, "Braking cannot reverse speed")
	check(motion.velocity_component(16384, 78643, 0) == 78643, "Quarter-turn heading")
	check(motion.velocity_component(49152, 78643, 0) == -78643, "Negative heading component")
	check(motion.velocity_component(65535, 78643, 0) == 0, "Heading wraps through lookup quantization")
	var state := {"speed": 0, "turn_step": 1, "movement_flags": 0, "attached": false,
		"rate1": 100, "rate2": 200, "unit_flags": 0x10000}
	var transition: Dictionary = Motion.animation_transition(state)
	check(transition.callbacks == ["StartMoving", "MoveRate1"], "Turning in place starts walk callback")
	check(transition.unit_flags == 0x10004, "Unrelated unit flags survive transition")
	state.unit_flags = transition.unit_flags
	check(Motion.animation_transition(state).callbacks.is_empty(), "Unchanged rate emits nothing")
	state.speed = 100
	check(Motion.animation_transition(state).callbacks.is_empty(), "Rate threshold equality remains in rate 1")
	state.speed = 101
	check(Motion.animation_transition(state).callbacks == ["MoveRate2"], "Rate changes do not restart walking")
	state.speed = 201
	check(Motion.animation_transition(state).callbacks == ["MoveRate3"], "Third movement rate")
	state.movement_flags = 4
	check(Motion.animation_transition(state).callbacks == ["StopMoving"], "Blocked movement stops script even with speed")
	state.movement_flags = 0
	state.attached = true
	check(Motion.animation_transition(state).callbacks == ["StopMoving"], "Attached units suppress locomotion script")
	print("GROUND_MOTION %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
