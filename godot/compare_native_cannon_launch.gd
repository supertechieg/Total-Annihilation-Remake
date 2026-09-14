extends SceneTree
## Host replay of native_cannon_launch.py engagements using combat_world's composition helpers.
const VM = preload("res://cob_vm.gd")
const Catalog = preload("res://unit_catalog.gd")
const Queries = preload("res://weapon_queries.gd")
const Origin = preload("res://piece_origin.gd")
const Launch = preload("res://ballistic_launch.gd")
const Motion = preload("res://ballistic_motion.gd")
const Combat = preload("res://combat_world.gd")

## JSON numbers parse as floats; compare nested values as integers.
static func integers(value: Variant) -> Variant:
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return integers(item))
	if value is Dictionary:
		var result := {}
		for key: String in value:
			result[key] = integers(value[key])
		return result
	if value is float or value is int:
		return int(value)
	return value

func _initialize() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../local/ballistics/cannon-launch.json"))
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var launch := Launch.new()
	var mismatches: Array = []
	var summary := {}
	for case: Dictionary in trace.cases:
		var unit: String = case.unit
		var model: Dictionary = catalog.load_unit(unit).model
		var weapon: Dictionary = catalog.weapon(str(catalog.definition(unit).weapon1))
		var vm := VM.new(catalog.load_script(unit))
		vm.read_values = {4: 100, 17: 0}
		vm.invoke("Create")
		var queries := Queries.new(vm)
		var offset := Launch.initial_offset(int(Origin.model_origin(model, vm.pieces, queries.piece_name(false), [0, 32768, 0])[2]),
			int(Origin.model_origin(model, vm.pieces, queries.piece_name(true), [0, 32768, 0])[2]))
		var unit_raw: Array = case.unit_raw
		var unit_heading := int(case.unit_heading)
		var target_raw: Array = case.target
		var speed := int(weapon.runtime.velocity_raw_per_tick)
		var gravity := int(case.gravity)
		var requested := []
		var requests: Array = []
		var angles: Array = []
		for step in range(90):
			var aim_raw := Combat.offset_point(unit_raw, Origin.model_origin(model, vm.pieces, queries.piece_name(true), [0, unit_heading, 0]))
			angles = Combat.ballistic_angles(aim_raw, target_raw, unit_heading, speed, gravity, float(weapon.runtime.minimum_barrel_angle))
			if int(angles[1]) != 0x8000 and angles != requested:
				vm.invoke("AimPrimary", angles)
				requested = angles
				requests.append({"step": step, "heading": int(angles[0]) & 0xffff, "pitch": int(angles[1]) & 0xffff})
			vm.step()
		var actual := {"offset": offset, "requests": requests}
		var expected: Dictionary = case.expected
		if not requested.is_empty():
			var start := Combat.offset_point(unit_raw, Origin.model_origin(model, vm.pieces, queries.piece_name(false), [0, unit_heading, 0]))
			var velocity: Array = launch.velocity(int(requested[0]) + unit_heading, int(requested[1]), speed, gravity, offset)
			var path: Array = []
			var position := start
			for step in range(1, 41):
				var next := Motion.integrate(position, velocity, gravity, [0, 0, 0])
				position = next.position
				velocity = next.velocity
				path.append(position)
			actual.merge({"start": start, "velocity": launch.velocity(int(requested[0]) + unit_heading, int(requested[1]), speed, gravity, offset), "path": path})
		var checks := {"offset": int(actual.offset) == int(expected.offset),
			"requests": integers(actual.requests) == integers(case.requests),
			"start": actual.has("start") and integers(actual.start) == integers(expected.get("start")),
			"velocity": actual.has("velocity") and integers(actual.velocity) == integers(expected.get("velocity")),
			"path": actual.has("path") and integers(actual.path.slice(0, expected.get("path", []).size())) == integers(expected.get("path"))}
		for key: String in checks:
			summary[key] = int(summary.get(key, 0)) + int(checks[key])
		if checks.values().has(false) and mismatches.size() < 4:
			mismatches.append({"unit": unit, "target": target_raw, "checks": checks,
				"host": {"offset": actual.offset, "requests": actual.requests.slice(-2), "start": actual.get("start"), "velocity": actual.get("velocity")},
				"native": {"offset": expected.offset, "requests": case.requests.slice(-2), "start": expected.get("start"), "velocity": expected.get("velocity")}})
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "matching": summary, "mismatches": mismatches,
		"scope": "Original 0x49e070 creation offset, AimFrom/atan/0x49a890 aim loop driving the original AimPrimary script for 90 ticks, turret fire 0x49d580 with muzzle query and launcher 0x49cde0, then 40 updates of 0x49b720; collision, sound and script-start effects stubbed; full health, zero accuracy/experience and zero wind drift"}
	FileAccess.open("res://../local/ballistics/cannon-launch-comparison.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	FileAccess.open("res://../analysis/native-cannon-launch-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true) + "\n")
	print("NATIVE_CANNON_LAUNCH %d cases; matching %s" % [trace.cases.size(), JSON.stringify(summary)])
	quit(0 if mismatches.is_empty() else 1)
