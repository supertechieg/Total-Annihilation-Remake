extends SceneTree
const Aim = preload("res://ballistic_aim.gd")

func _initialize() -> void:
	# Fixed expected angles from the original executable; delta is source minus target.
	var cases := [
		[[8388608, -2097152, 0], 0.0, 5497],
		[[8388608, 0, 0], 0.0, 2706],
		[[8388608, 2097152, 0], 0.0, 20],
		[[15728640, -2097152, 0], 0.0, 32768],
		[[15728640, 0, 0], 0.0, 6229],
		[[16911793, 0, 0], 0.0, 8190],
		[[16911794, 0, 0], 0.0, 32768],
		[[0, 0, 0], 0.0, 32768],
		[[8388608, 0, 0], 0.7853981852531433, 32768],
	]
	var failures := 0
	for case: Array in cases:
		var actual := Aim.solve(case[0], 371370, 8155, case[1])
		if actual != int(case[2]):
			failures += 1
			printerr("FAIL: ballistic aim ", case, " returned ", actual)
	print("BALLISTIC_AIM %d / %d checks pass" % [cases.size() - failures, cases.size()])
	quit(0 if failures == 0 else 1)
