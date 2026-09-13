extends SceneTree
const Catalog = preload("res://unit_catalog.gd")

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	if not catalog.fault.is_empty():
		printerr(catalog.fault)
		quit(1)
		return
	var checks := 0
	var errors: Array = []
	for unit_id: String in catalog.index.units:
		var unit: Dictionary = catalog.load_unit(unit_id)
		var script: Dictionary = catalog.load_script(unit_id)
		checks += 1
		if unit.is_empty() or unit.model == null or script.is_empty():
			errors.append("Incomplete unit " + unit_id)
			continue
		var piece_names: Array = []
		for piece: Dictionary in unit.model.pieces:
			piece_names.append(String(piece.name).to_lower())
		for name: String in script.pieces:
			checks += 1
			if name.to_lower() not in piece_names:
				errors.append("Script/model piece mismatch: " + unit_id + ":" + name)
		for texture: String in unit.model.textures:
			checks += 1
			if not catalog.index.textures.has(texture) or not FileAccess.file_exists(catalog.root.path_join(catalog.index.textures[texture])):
				errors.append("Missing texture: " + texture)
	for builder: String in catalog.index.build_menus:
		for unit_id: String in catalog.build_options(builder):
			checks += 1
			if catalog.definition(unit_id).is_empty():
				errors.append("Missing build option: " + unit_id)
	for unit_id: String in ["armcom", "corcom"]:
		checks += 1
		if catalog.build_options(unit_id).is_empty():
			errors.append("Commander has no build menu")
	var report := {"checks": checks, "units": catalog.index.units.size(), "errors": errors,
		"scope": "Bundle references and model/script piece names; does not execute all unit scripts or validate simulation"}
	FileAccess.open(catalog.root.path_join("validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	for error: String in errors.slice(0, 10):
		printerr(error)
	print("UNIT_CATALOG %d units, %d checks, %d errors" % [catalog.index.units.size(), checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
