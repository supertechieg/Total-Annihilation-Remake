extends SceneTree
## Native-derived fixtures from native_cannon_launch.py (Thud, aimed heading 49058 absolute, pitch 142).
const Combat = preload("res://combat_world.gd")
const GameRandom = preload("res://wind_state.gd")

func spread(health: int, maxdamage: int, experience: int, accuracy: int, seed: int) -> Array:
	var rng := GameRandom.new()
	rng.game_seed = seed
	var result := Combat.firing_spread(49058, 142, accuracy, health, maxdamage, experience, rng)
	return [int(result[0]), int(result[1]), rng.game_seed]

func _initialize() -> void:
	var fixtures := [
		[[1000, 1000, 0, 0, 1], [49058, 142, 1]],
		[[500, 1000, 0, 0, 1], [48969, 383, 282475249]],
		[[1, 1000, 0, 0, 12345], [49682, 337, 1790989824]],
		[[999, 1000, 0, 0, 777], [49057, 141, 439936479]],
		[[1000, 1000, 0, 400, 99991], [49195, 157, 1277697415]],
		[[250, 1000, 12, 0, 2024], [49402, 65024, 499253874]],
		[[250, 1000, 17, 0, 31337], [48673, 640, 2146768626]],
		[[100, 1000, 600, 300, 424242], [49076, 136, 1834632717]],
		[[1058, 1058, 0, 0, 5], [49058, 142, 5]],
		[[300, 700, 0, 65000, 2147483646], [49086, 65424, 1865008398]]]
	var failures := 0
	for fixture: Array in fixtures:
		var inputs: Array = fixture[0]
		var actual := spread(inputs[0], inputs[1], inputs[2], inputs[3], inputs[4])
		if actual != fixture[1]:
			failures += 1
			printerr("Spread mismatch for ", inputs, ": ", actual, " expected ", fixture[1])
	print("FIRING_SPREAD %d / %d checks pass" % [fixtures.size() - failures, fixtures.size()])
	quit(0 if failures == 0 else 1)
