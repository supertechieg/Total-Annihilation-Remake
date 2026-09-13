extends SceneTree
const Damage = preload("res://weapon_damage.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/splash/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-damage.json")))
	var mismatches := 0
	for case: Dictionary in trace.cases:
		var definition := {"default": int(case.base)}
		if int(case.override_mode) > 0:
			definition["corraid" if int(case.override_mode) == 1 else "armflash"] = int(case.override)
		var base := Damage.base_damage(definition, "corraid")
		var actual := Damage.amount(base, float(case.multiplier), int(case.experience), int(case.flags), case.has_source)
		if actual != int(case.expected):
			mismatches += 1
	var report := {"exe_sha256": trace.exe_sha256, "cases": trace.cases.size(), "mismatches": mismatches,
		"scope": "Original damage selection, float32 multiplier truncation, attacker experience and global doubling/halving flags; health dispatch stubbed; excludes armor, kills and damage callbacks"}
	FileAccess.open(folder.path_join("native-damage-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NATIVE_DAMAGE_COMPARISON %d / %d cases match" % [trace.cases.size() - mismatches, trace.cases.size()])
	quit(0 if mismatches == 0 else 1)
