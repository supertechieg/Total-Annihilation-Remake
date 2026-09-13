extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Visuals = preload("res://unit_visuals.gd")

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	if not catalog.fault.is_empty():
		printerr(catalog.fault)
		quit(1)
		return
	var visuals = Visuals.new(catalog)
	var count := 0
	var failures := 0
	for unit_id: String in catalog.index.units:
		var instance: Node3D = visuals.instantiate(unit_id)
		if instance.get_meta("pieces").size() != catalog.load_unit(unit_id).model.pieces.size():
			failures += 1
		instance.free()
		count += 1
	var first: Node3D = visuals.instantiate("armcom")
	var second: Node3D = visuals.instantiate("armcom")
	var first_rig: Dictionary = first.get_meta("rig")
	var second_rig: Dictionary = second.get_meta("rig")
	for key: String in first_rig:
		if first_rig[key] == second_rig[key]:
			failures += 1
		if first_rig[key].get_child_count() > 0 and first_rig[key].get_child(0) is MeshInstance3D:
			if first_rig[key].get_child(0).mesh != second_rig[key].get_child(0).mesh:
				failures += 1
	first.free()
	second.free()
	print("UNIT_VISUALS %d models instantiated; %d failures; repeated units share mesh resources" % [count, failures])
	quit(0 if failures == 0 else 1)
