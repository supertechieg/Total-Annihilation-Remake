extends SceneTree
## Headless integration for viewer faction selection.
## Boots the viewer as Core, verifies Core Commander model/script/build menu/movement/solar construction,
## then switches back to Arm through the same restart path used by the UI selector and confirms Arm is restored.

func fail(label: String) -> void:
	printerr("FAIL " + label)
	quit(1)

func run() -> void:
	root.gui_embed_subwindows = true
	# Boot Core through the same meta channel the UI selector uses.
	set_meta("faction", "core")
	var scene: PackedScene = load("res://viewer.tscn")
	var viewer = scene.instantiate()
	root.add_child(viewer)
	current_scene = viewer
	await process_frame
	if viewer.faction != "core" or viewer.commander_type != "corcom":
		fail("Core boot: faction=" + str(viewer.faction) + " commander_type=" + str(viewer.commander_type))
		return
	if viewer.script_vm == null or not viewer.script_vm.fault.is_empty():
		fail("Core commander script not loaded cleanly: " + str(viewer.script_vm.fault if viewer.script_vm else "null"))
		return
	if viewer.economy == null or not viewer.economy.units.has(viewer.economy.builder_id):
		fail("Core commander missing from economy")
		return
	var commander_id: int = viewer.economy.builder_id
	if viewer.economy.units[commander_id].type != "corcom":
		fail("Economy commander is not corcom: " + str(viewer.economy.units[commander_id].type))
		return
	var build_options: Array = viewer.unit_catalog.build_options("corcom")
	if "corsolar" not in build_options or "cormex" not in build_options:
		fail("Core build menu missing resource buildings: " + str(build_options))
		return
	# Move a short distance to exercise Core movement/StartMoving/StopMoving.
	var start_position: Vector2 = viewer.unit_position
	var destination: Vector2 = viewer.navigation.nearest_open(start_position + Vector2(96, -64))
	if not viewer.issue_move(destination):
		fail("Core commander refused move order")
		return
	for tick in range(1500):
		viewer.step_script()
		if viewer.unit_position.distance_to(destination) < 3.0 and viewer.mobile.speed == 0 and viewer.mobile.route.is_empty():
			break
	if viewer.unit_position.distance_to(destination) >= 3.0:
		fail("Core commander did not arrive: " + str(viewer.unit_position))
		return
	if viewer.mobile.speed != 0 or not viewer.mobile.route.is_empty():
		fail("Core commander did not settle after arrival: speed=" + str(viewer.mobile.speed))
		return
	if not viewer.script_vm.fault.is_empty():
		fail("Core commander script fault after movement: " + viewer.script_vm.fault)
		return
	# Build a corsolar through the same placement path as the UI.
	var solar_point: Vector2 = (viewer.unit_position + Vector2(80, 0)).snapped(Vector2(16, 16))
	if not viewer.place_structure("corsolar", solar_point):
		fail("place_structure(corsolar) rejected: " + str(viewer.economy.status))
		return
	var built_id: int = viewer.economy.task_id
	if built_id == 0 or not viewer.economy.units.has(built_id):
		fail("corsolar task_id missing after placement")
		return
	for tick in range(2400):
		viewer.step_script()
		if float(viewer.economy.units[built_id].remaining) == 0.0:
			break
	if float(viewer.economy.units[built_id].remaining) != 0.0:
		fail("corsolar never completed; remaining=" + str(viewer.economy.units[built_id].remaining))
		return
	if not viewer.economy.scripts[built_id].fault.is_empty():
		fail("corsolar script fault: " + viewer.economy.scripts[built_id].fault)
		return
	print("CORE_SCENARIO_OK moved=%s built=corsolar id=%d" % [viewer.unit_position, built_id])
	# Actual reload path while Core is already selected: the UI does this when a scenario ends.
	var viewer_iid: int = viewer.get_instance_id()
	reload_current_scene()
	await process_frame
	await process_frame
	var retained = current_scene
	if retained == null or retained.get_instance_id() == viewer_iid:
		fail("reload_current_scene did not produce a fresh scene while Core selected")
		return
	if retained.faction != "core" or retained.commander_type != "corcom":
		fail("Reload lost Core selection: faction=" + str(retained.faction))
		return
	if retained.script_vm == null or not retained.script_vm.fault.is_empty():
		fail("Reloaded Core commander script not clean: " + str(retained.script_vm.fault if retained.script_vm else "null"))
		return
	if retained.economy == null or not retained.economy.units.has(retained.economy.builder_id):
		fail("Reloaded Core commander missing from economy")
		return
	if retained.economy.units[retained.economy.builder_id].type != "corcom":
		fail("Reloaded economy commander is not corcom")
		return
	var retained_model_root: Node3D = retained.model_root
	if retained_model_root == null or retained_model_root.get_meta("pieces", []).size() == 0:
		fail("Reloaded Core model missing pieces meta")
		return
	var retained_build_options: Array = retained.unit_catalog.build_options("corcom")
	if "corsolar" not in retained_build_options or "cormex" not in retained_build_options:
		fail("Reloaded Core build menu missing verified resource buildings")
		return
	# Switch to Arm via the UI helper and confirm reload replaces the scene.
	var retained_iid: int = retained.get_instance_id()
	retained.switch_faction("arm")
	await process_frame
	await process_frame
	var fresh = current_scene
	if fresh == null or fresh.get_instance_id() == retained_iid:
		fail("switch_faction(arm) did not produce a fresh scene")
		return
	if fresh.faction != "arm" or fresh.commander_type != "armcom":
		fail("Restart to Arm did not apply: faction=" + str(fresh.faction))
		return
	if fresh.economy == null or fresh.economy.units.get(fresh.economy.builder_id, {}).get("type", "") != "armcom":
		fail("Arm commander missing or wrong type after restart")
		return
	# Flip back to Core through the helper and verify a fresh Core scene loads.
	var fresh_iid: int = fresh.get_instance_id()
	fresh.switch_faction("core")
	await process_frame
	await process_frame
	var again = current_scene
	if again == null or again.get_instance_id() == fresh_iid:
		fail("switch_faction(core) did not reload the scene")
		return
	if again.faction != "core" or again.commander_type != "corcom":
		fail("Second faction switch failed to restore Core")
		return
	print("FACTION_SELECTION_OK reload retained Core; switch_faction reloaded Arm and Core cleanly")
	quit(0)

func _initialize() -> void:
	call_deferred("run")
