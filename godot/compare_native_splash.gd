extends SceneTree
const Splash = preload("res://splash_damage.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/splash/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-falloff.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var actual := Splash.multiplier(case.point, case.center, case.lower, case.upper, int(case.radius), float(case.edge))
		if actual != float(case.expected):
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original blast-to-axis-aligned-unit-box distance and float32 falloff; supplied bounds/radius/edge; excludes target enumeration, bound generation, damage dispatch and features"}
	FileAccess.open(folder.path_join("native-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_SPLASH_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
