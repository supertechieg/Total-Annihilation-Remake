extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var viewer = load("res://viewer.tscn").instantiate()
	root.add_child(viewer)
	current_scene = viewer
	viewer.set_process(false)
	viewer.resource_label.text = preload("res://resource_display.gd").describe({"metal": 125.0, "metal_storage": 2000.0, "metal_income": 6.7, "metal_requested": 12.5, "metal_debt": 24.8, "energy": 0.0, "energy_storage": 2000.0, "energy_income": 40.0, "energy_requested": 83.5, "energy_debt": 61.2})
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../local/resource-display.png")
	var error := root.get_texture().get_image().save_png(path)
	print("RESOURCE_DISPLAY capture=", path)
	quit(0 if error == OK else 1)
