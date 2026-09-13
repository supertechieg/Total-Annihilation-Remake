extends SceneTree
const Motion = preload("res://ballistic_motion.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var position := [0, 12 * 65536, 0]
	var velocity := [371370, 196608, 0]
	var first := Motion.integrate(position, velocity, 8155, [0, 0, 0])
	check(first.position == [371370, 15 * 65536, 0] and first.velocity == [371370, 188453, 0], "First shell step moves before applying gravity")
	check(position == [0, 12 * 65536, 0] and velocity == [371370, 196608, 0], "Inputs remain unchanged for swept collision")
	for tick in range(120):
		var next := Motion.integrate(position, velocity, 8155, [0, 0, 0])
		position = next.position
		velocity = next.velocity
	check(position == [44564400, -33847308, 0] and velocity == [371370, -781992, 0], "120-step native fixture arc ascends and falls with unchanged horizontal speed")
	var drifted := Motion.integrate([1, 2, 3], [4, 5, 6], 0, [-10, 20, -30])
	check(drifted.position == [-5, 27, -21] and drifted.velocity == [4, 5, 6], "Map drift affects position without accelerating the shell")
	var overflow := Motion.integrate([2147483647, -2147483648, 0], [1, -1, 0], 2147483647, [0, 0, 0])
	check(overflow.position == [-2147483648, 2147483647, 0] and overflow.velocity[1] == -2147483648, "Native signed 32-bit wrap is retained")
	check(Motion.expiration(100, 100, 0, true) == 0, "Zero weapon timer bypasses expiry even with burnblow")
	check(Motion.expiration(99, 100, 30, false) == 0, "Shell remains live before deadline")
	check(Motion.expiration(100, 100, 30, false) == 1, "Deadline expires a non-burnblow shell")
	check(Motion.expiration(100, 100, 30, true) == 2, "Burnblow requests impact on the deadline")
	check(Motion.expiration(0, 0xffffffff, 1, false) == 0, "Deadline comparison is unsigned")
	print("BALLISTIC_MOTION %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
