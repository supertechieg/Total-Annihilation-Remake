extends SceneTree
const Bounds = preload("res://unit_bounds.gd")
const Catalog = preload("res://unit_catalog.gd")

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	# Heights captured from the original recursive model routine.
	var fixtures := {"armcom": 2621439, "armflash": 557056, "corraid": 781833,
		"armlab": 966655, "armsolar": 2524989, "armvp": 2457600}
	var failures := 0
	for unit: String in fixtures:
		if Bounds.from_unit(catalog.load_unit(unit)).upper[1] != fixtures[unit]:
			failures += 1
	var flash := Bounds.from_unit(catalog.load_unit("armflash"))
	if flash.lower != [-1048576, 0, -1048576] or flash.upper != [1048576, 557056, 1048576]:
		failures += 1
	print("UNIT_BOUNDS %d / 7 checks pass" % [7 - failures])
	quit(0 if failures == 0 else 1)
