extends SceneTree
const Collision = preload("res://projectile_collision.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/collision/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-projectile.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var cell := Collision.cell_index(case.position, 4, 4)
		var target := Collision.unit_target(int(case.position[1]), int(case.owner), case.occupants) if cell >= 0 else 0
		if cell != int(case.cell) or target != int(case.target) or (cell < 0) != bool(case.expired):
			mismatches += 1
	var terrain_mismatches := 0
	var differences: Array = []
	for case: Dictionary in trace.get("terrain_cases", []):
		var actual := Collision.terrain_contact(case)
		var expected: Dictionary = case.expected
		var matches: bool = bool(actual.impact) == (int(expected.impacts) > 0) and int(expected.impacts) <= 1 \
			and int(actual.velocity_y) == int(expected.velocity_y) and int(actual.surface) == int(expected.surface) \
			and int(actual.cache[0]) == int(expected.cache[0]) and int(actual.cache[1]) == int(expected.cache[1]) and not bool(expected.removed)
		if not matches:
			terrain_mismatches += 1
			if differences.size() < 3:
				differences.append({"case": case, "actual": actual})
	var terrain_count: int = trace.get("terrain_cases", []).size()
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"terrain_cases": terrain_count, "terrain_mismatches": terrain_mismatches, "differences": differences,
		"scope": "Original endpoint grid lookup and two unit slots including ownership and height boundaries; plus the terrain/feature/water branch with empty unit slots: unitsonly, feature anchors/continuations/sentinels and heights, last-feature-cell cache, lowest-corner terrain height, groundbounce, waterweapon, sea level and map lava flag. Excludes grid population, projectile proximity and impact dispatch effects"}
	FileAccess.open(folder.path_join("native-projectile-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("PROJECTILE_COLLISION %d / %d native unit cases match; %d / %d terrain cases match" % [trace.cases.size() - mismatches, trace.cases.size(), terrain_count - terrain_mismatches, terrain_count])
	quit(0 if mismatches == 0 and terrain_mismatches == 0 else 1)
