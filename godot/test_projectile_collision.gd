extends SceneTree
const Collision = preload("res://projectile_collision.gd")

func _initialize() -> void:
	var checks := [
		Collision.cell_index([1301175, 327680, 3233831], 4, 4) == 13,
		Collision.cell_index([3316926, 327680, 3030526], 4, 4) == 11,
		Collision.cell_index([-1, 0, 0], 4, 4) == -1,
		Collision.cell_index([4194304, 0, 0], 4, 4) == -1,
		Collision.unit_target(327680, 0, [
			{"id": 1, "owner": 1, "bottom": 0, "top": 327680},
			{"id": 2, "owner": 0, "bottom": 0, "top": 1572864}]) == 0,
		Collision.unit_target(327680, 1, [
			{"id": 1, "owner": 1, "bottom": -589824, "top": 1703936},
			{"id": 2, "owner": 0, "bottom": 327680, "top": 1441792}]) == 2]
	var failures := checks.count(false)
	print("PROJECTILE_COLLISION %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
