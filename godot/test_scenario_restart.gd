extends SceneTree
func _initialize() -> void:
	root.gui_embed_subwindows = true
	call_deferred("run")
func run() -> void:
	var scene: PackedScene = load("res://viewer.tscn")
	var viewer = scene.instantiate()
	root.add_child(viewer)
	current_scene = viewer
	viewer.start_opponent()
	if viewer.opponent == null:
		quit(1)
		return
	for id: int in viewer.economy.units.keys():
		if int(viewer.economy.units[id].get("team", 0)) == 1:
			viewer.economy.remove_unit(id)
	viewer.check_scenario_result()
	var dialog: AcceptDialog
	for child in viewer.get_children():
		if child is AcceptDialog:
			dialog = child
	if dialog == null or not dialog.visible or dialog.get_ok_button().text != "Restart":
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../local/result-dialog.png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		quit(1)
		return
	# Invoke the dialog's confirmation action, exercising its connected reload.
	dialog.confirmed.emit()
	await process_frame
	await process_frame
	var fresh = current_scene
	var passed: bool = fresh != null and fresh != viewer and fresh.opponent == null and fresh.scenario_result == null and fresh.economy.units.has(fresh.economy.builder_id)
	print("SCENARIO_RESTART ", "PASS" if passed else "FAIL", " capture=", path)
	quit(0 if passed else 1)
