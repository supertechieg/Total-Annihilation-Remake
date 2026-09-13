extends SceneTree
const Splash = preload("res://splash_damage.gd")

func _initialize() -> void:
	var zero := [0, 0, 0]
	var fixtures := [[0, 1.0], [524288, 0.25], [983040, 0.00390625], [1048576, 0.0], [65535, 1.0], [65536, 0.87890625]]
	var failures := 0
	for fixture: Array in fixtures:
		if Splash.multiplier([fixture[0], 0, 0], zero, zero, zero, 16, 0.0) != float(fixture[1]):
			failures += 1
	print("SPLASH_DAMAGE %d / %d checks pass" % [fixtures.size() - failures, fixtures.size()])
	quit(0 if failures == 0 else 1)
