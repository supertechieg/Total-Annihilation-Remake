extends SceneTree
const Launch = preload("res://ballistic_launch.gd")

func _initialize() -> void:
	var launch := Launch.new()
	# Native examples cover quantized angles, unsigned travel and gravity adjustment.
	var cases := [
		[32222, 25421, 371370, 8155, 0, [17232, 242578, -280687]],
		[57177, 41662, 655359, 0, 655358, [-314437, -490959, 299385]],
		[63665, 5321, 218453, 16000, 218453, [35020, 89333, -188162]],
		[1349, 18168, 1000000, 8155, 1000001, [20939, 977074, 169727]],
		[41714, 23825, 371370, 0, 4294967295, [-183681, 281202, -158452]],
		[2190, 34414, 655359, 16000, 1632245313, [134036, -39944080, 632980]],
	]
	var failures := 0
	for case: Array in cases:
		var actual := launch.velocity(case[0], case[1], case[2], case[3], case[4])
		if actual != case[5]:
			failures += 1
			printerr("FAIL: ballistic launch ", case, " returned ", actual)
	print("BALLISTIC_LAUNCH %d / %d checks pass" % [cases.size() - failures, cases.size()])
	quit(0 if failures == 0 else 1)
