extends SceneTree
const Origin = preload("res://piece_origin.gd")

func _initialize() -> void:
	var pieces := [
		{"parent": -1, "offset": [0, 0, 0], "move": [0, 0, 0], "rotation": [0, 0, 0]},
		{"parent": 0, "offset": [65536, 0, 0], "move": [0, 0, 0], "rotation": [8192, 8192, 8192]},
	]
	var checks: Array = []
	checks.append(Origin.origin(pieces, 1, [0, 0, 0]) == [65536, 0, 0])
	checks.append(Origin.origin(pieces, 1, [0, 16384, 0]) == [0, 0, -65536])
	pieces[0].rotation[1] = 16384
	checks.append(Origin.origin(pieces, 1, [0, 16384, 0]) == [-65536, 0, 0])
	pieces[0].offset = [10, 20, 30]
	pieces[0].move = [1, 2, 3]
	checks.append(Origin.origin(pieces, 0, [4096, 8192, 16384]) == [11, 22, -33])
	checks.append(Origin.origin(pieces, -1, [0, 0, 0]) == [0, 0, 0])
	checks.append(Origin.nearest_even(2.5) == 2 and Origin.nearest_even(3.5) == 4 and Origin.nearest_even(-2.5) == -2 and Origin.nearest_even(-3.5) == -4)
	var failures := checks.count(false)
	print("PIECE_ORIGIN %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
