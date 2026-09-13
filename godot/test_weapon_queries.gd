extends SceneTree
const VM = preload("res://cob_vm.gd")
const Catalog = preload("res://unit_catalog.gd")
const Queries = preload("res://weapon_queries.gd")

func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var checks := 0
	var failures := 0
	for unit: String in ["armflash", "corraid"]:
		var vm := VM.new(catalog.load_script(unit))
		var queries := Queries.new(vm)
		var aim := queries.piece_name(true)
		checks += 1
		if aim.is_empty() or not queries.fault.is_empty():
			failures += 1
		var muzzle := queries.piece_name()
		vm.functions.erase("AimFromPrimary")
		checks += 1
		if queries.piece_name(true) != muzzle:
			failures += 1
		checks += 1
		if not vm.completions.is_empty():
			failures += 1
	print("WEAPON_QUERIES %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
