extends SceneTree
const Collision = preload("res://projectile_collision.gd")
const WorldCollision = preload("res://world_collision.gd")
const Navigation = preload("res://terrain_navigation.gd")

func contact(flags: int, y: int, low: int, extra := {}) -> Dictionary:
	var input := {"flags": flags, "position": [8 * 65536, y, 8 * 65536], "cell": {"low": low, "high": low + 4, "code": 0xffff},
		"anchor_code": 0xffff, "feature_count": 0, "feature_heights": [], "sea": 0, "lava": 0, "velocity_y": -400000, "cache": [-32768, -32768]}
	input.merge(extra, true)
	return Collision.terrain_contact(input)

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
	# Integer height below the cell's lowest corner impacts; equal or above does not.
	checks.append(contact(0, 23 * 65536 + 65535, 24).impact)
	checks.append(not contact(0, 24 * 65536, 24).impact)
	# unitsonly skips the whole branch; groundbounce reflects a quarter of vertical speed instead of impacting.
	checks.append(not contact(0x4000, 0, 24).impact)
	var bounce := contact(0x8000, 0, 24)
	checks.append(not bounce.impact and int(bounce.velocity_y) == 100000)
	# Above terrain but under sea level impacts unless it is a water weapon or the map is lava.
	checks.append(contact(0, 30 * 65536, 24, {"sea": 31}).impact)
	checks.append(not contact(0x10000, 30 * 65536, 24, {"sea": 31}).impact)
	checks.append(not contact(0, 30 * 65536, 24, {"sea": 31, "lava": 1}).impact)
	checks.append(int(contact(0, 0, 24).surface) == 26)
	# A feature impacts once per feature cell; the repeated cell falls through to the terrain test.
	var feature := contact(0, 30 * 65536, 24, {"cell": {"low": 24, "high": 24, "code": 0}, "feature_count": 1, "feature_heights": [10]})
	checks.append(feature.impact and feature.cache == [0, 0])
	checks.append(not contact(0, 30 * 65536, 24, {"cell": {"low": 24, "high": 24, "code": 0}, "feature_count": 1, "feature_heights": [10], "cache": [0, 0]}).impact)
	# Live world uses the floored endpoint cell and its lowest corner, not the nearest raw height sample.
	var heights := PackedByteArray()
	heights.resize(8 * 8)
	heights.fill(0)
	for z in range(8):
		for x in range(4, 8):
			heights[z * 8 + x] = 24
	var world := {"navigation": Navigation.new(8, 8, heights)}
	var collision := WorldCollision.new(8, 8)
	var edge := {"position_raw": [roundi(61.0 * 65536), 23 * 65536, 40 * 65536], "velocity_raw": [0, 0, 0]}
	checks.append(not collision.terrain_impact(DictWorld.new(world), edge, 0))
	var inside := {"position_raw": [roundi(65.0 * 65536), 23 * 65536, 40 * 65536], "velocity_raw": [0, 0, 0]}
	checks.append(collision.terrain_impact(DictWorld.new(world), inside, 0))
	var failures := checks.count(false)
	if failures:
		printerr("Projectile collision checks: ", checks)
	print("PROJECTILE_COLLISION %d / %d checks pass" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)

class DictWorld extends RefCounted:
	var navigation: RefCounted
	func _init(source: Dictionary) -> void:
		navigation = source.navigation
