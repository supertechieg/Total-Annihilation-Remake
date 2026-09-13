extends SceneTree
const Damage = preload("res://weapon_damage.gd")

func _initialize() -> void:
	# Captured outputs from original 0x499cd0, not calculated expectations.
	var fixtures := [
		[60312, 0.0, 38, 0, false, 0],
		[7573, 0.1, 32, 128, true, 1968],
		[28815, 0.5, 14, 256, true, 8067],
		[11459, 1.0, 38, 384, true, 14896],
		[7122, 1.5, 34, 0, true, 13887],
		[58610, 0.1, 38, 256, true, 3809],
		[5471, 0.5, 1, 384, false, 2735]]
	var failures := 0
	for fixture: Array in fixtures:
		if Damage.amount(fixture[0], fixture[1], fixture[2], fixture[3], fixture[4]) != fixture[5]:
			failures += 1
	if Damage.base_damage({"default": 59929, "corraid": 7573}, "corraid") != 7573:
		failures += 1
	if Damage.base_damage({"default": 28815, "armflash": 6320}, "corraid") != 28815:
		failures += 1
	print("WEAPON_DAMAGE %d / 9 checks pass" % [9 - failures])
	quit(0 if failures == 0 else 1)
