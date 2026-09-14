extends SceneTree
## Compare feature_damage.gd with native 0x485070 heights and the 0x49a120 splash feature pass.
const FeatureDamage = preload("res://feature_damage.gd")

func integers(values: Array) -> Array:
	return values.map(func(value): return integers(value) if value is Array else int(value))

func _initialize() -> void:
	var path := ProjectSettings.globalize_path("res://../local/features/native-feature-damage.json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		printerr("Run tools/native_feature_damage.py first")
		quit(1)
		return
	var size := int(data.size)
	var checks := 0
	var failures := 0
	for case: Dictionary in data.heights:
		var heights := PackedByteArray(integers(case.heights))
		var actual := FeatureDamage.height(heights, size, size, int(case.x), int(case.z))
		checks += 1
		if actual != int(case.result):
			failures += 1
			if failures <= 5:
				printerr("height x=%d z=%d expected %d got %d" % [int(case.x), int(case.z), int(case.result), actual])
	for index in range(data.splash.size()):
		var case: Dictionary = data.splash[index]
		var definitions: Array = case.definitions.map(func(item): return {"footprintx": int(item.footprintx), "footprintz": int(item.footprintz), "damage": int(item.damage), "flags": int(item.flags)})
		var instances: Array = case.instances.map(func(item): return {"position": integers(item.position), "damage": int(item.damage), "x": int(item.x), "z": int(item.z)})
		var grid := FeatureDamage.ArrayGrid.new(size, size, PackedByteArray(integers(case.heights)), integers(case.codes), integers(case.words), integers(case.bits), definitions, instances)
		var weapon := {"default": int(case.weapon.default), "area": int(case.weapon.area), "firestarter": int(case.weapon.firestarter), "flags": int(case.weapon.flags)}
		var result := FeatureDamage.splash(grid, weapon, integers(case.position), int(case.game_flags))
		var fields := {"hits": [result.hits, integers(case.hits)], "replaced": [result.replaced, integers(case.replaced)],
			"ignited": [result.ignited, integers(case.ignited)], "words": [grid.words, integers(case.final_words)],
			"damage": [instances.map(func(item): return int(item.damage)), integers(case.final_damage)]}
		for key: String in fields:
			checks += 1
			if fields[key][0] != fields[key][1]:
				failures += 1
				if failures <= 8:
					printerr("splash %d %s expected %s got %s" % [index, key, fields[key][1], fields[key][0]])
		for param in case.replace_params:
			checks += 1
			if int(param) != 0:
				failures += 1
	print("FEATURE_DAMAGE_NATIVE %d / %d checks match (%d heights, %d splashes)" % [checks - failures, checks, data.heights.size(), data.splash.size()])
	quit(0 if failures == 0 else 1)
