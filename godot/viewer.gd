extends Control
## Original assets and COB, with a first controllable ground-movement slice.

const ASSET_RELATIVE = "../local/viewer-assets/"
const CobVM = preload("res://cob_vm.gd")
const UnitCatalog = preload("res://unit_catalog.gd")
const UnitVisuals = preload("res://unit_visuals.gd")
var unit_catalog: RefCounted
var unit_visuals: RefCounted
const Navigation = preload("res://terrain_navigation.gd")
const MobileUnit = preload("res://mobile_unit.gd")
const ConstructionWorld = preload("res://construction_world.gd")
var economy: RefCounted
var build_picker: OptionButton
var resource_label: Label
var placement_type := ""
var structure_sprites: Dictionary = {}
var structure_views: Dictionary = {}
var structure_models: Dictionary = {}
var navigation: RefCounted
var mobile: RefCounted
var route_line: Line2D
var assets: String
var scene_data: Dictionary
var unit_data: Dictionary
var terrain: Texture2D
var map_panel: Control
var world: Node2D
var terrain_sprite: Sprite2D
var unit_sprite: Sprite2D
var selection: Line2D
var model_view: SubViewport
var model_root: Node3D
var status_label: Label
var zoom_label: Label
var map_zoom := 1.4
var map_center := Vector2(3072, 3840)
var unit_position := Vector2(3072, 3840)
var heading := 0.0
var dragging := false
var piece_nodes: Array[Node3D] = []
var frames := 0
var script_vm: RefCounted
var rig_nodes: Dictionary = {}
var rig_origins: Dictionary = {}
var tick_accumulator := 0.0
var walking := false
var building := false
var pending_shot: Dictionary = {}
var walk_button: Button
var build_button: Button
var script_label: Label
var playback_paused := false

func image_texture(filename: String) -> ImageTexture:
	var image := Image.load_from_file(assets.path_join(filename))
	if image == null:
		push_error("Cannot load " + filename)
		return null
	return ImageTexture.create_from_image(image)

func label(text: String, font_size: int, color := Color("cad4d7")) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 34
	result.pressed.connect(action)
	return result

func _ready() -> void:
	assets = ProjectSettings.globalize_path("res://").path_join(ASSET_RELATIVE).simplify_path()
	if not FileAccess.file_exists(assets.path_join("scene.json")) or not FileAccess.file_exists(ProjectSettings.globalize_path("res://../local/unit-assets/index.json")):
		var message := label("Run 'Run Viewer.cmd' to prepare the original map and unit assets.", 22)
		message.position = Vector2(40, 40)
		add_child(message)
		push_error(message.text)
		if "--verify" in OS.get_cmdline_user_args():
			get_tree().quit(1)
		return
	scene_data = JSON.parse_string(FileAccess.get_file_as_string(assets.path_join("scene.json")))
	unit_data = JSON.parse_string(FileAccess.get_file_as_string(assets.path_join("unit.json")))
	terrain = image_texture("terrain.png")
	build_model()
	build_interface()
	start_script_runtime()
	start_world_movement()
	update_world()
	print("VIEWER_READY map=%s pieces=%d textures=%d" % [scene_data.name, unit_data.pieces.size(), unit_data.textures.size()])

func start_world_movement() -> void:
	var fields: Dictionary = unit_data.definition
	navigation = Navigation.new(int(scene_data.height_grid_width), int(scene_data.height_grid_height),
		FileAccess.get_file_as_bytes(assets.path_join("heights.bin")), int(scene_data.sea_level),
		int(fields.get("maxslope", "20")), int(fields.get("maxwaterdepth", "35")))
	unit_position = navigation.nearest_open(unit_position)
	assert(unit_position.x >= 0, "Map has no passable starting point")
	mobile = MobileUnit.new(navigation, fields, unit_position, script_vm)
	economy = ConstructionWorld.new(unit_catalog, navigation, unit_position)
	map_center = unit_position
	if "--move" in OS.get_cmdline_user_args():
		issue_move(unit_position + Vector2(128, -96))
	if "--construction-demo" in OS.get_cmdline_user_args():
		place_structure("armsolar", unit_position + Vector2(80, 0))
		for tick in range(600):
			step_script()

func issue_move(target: Vector2) -> bool:
	if mobile == null:
		return false
	if economy != null:
		economy.stop_build()
	if building:
		toggle_build()
	if not mobile.move_to(target):
		status_label.text = "  " + mobile.status
		return false
	if walking:
		walking = false
		script_vm.invoke("StopMoving")
		walk_button.text = "Play walk cycle  [Space]"
	route_line.points = mobile.route
	status_label.text = "  Move order accepted — %d route points" % mobile.route.size()
	return true

func stop_order() -> void:
	placement_type = ""
	if economy != null:
		economy.stop_build()
	if building:
		toggle_build()
	if walking:
		walking = false
		script_vm.invoke("StopMoving")
		walk_button.text = "Play walk cycle  [Space]"
	if mobile != null:
		mobile.stop()
		route_line.clear_points()
		status_label.text = "  Stop order — braking"

func choose_build() -> void:
	stop_order()
	placement_type = str(build_picker.get_item_metadata(build_picker.selected))
	var fields: Dictionary = unit_catalog.definition(placement_type)
	status_label.text = "  Place %s nearby · %s metal / %s energy · Right-click cancels" % [fields.name, fields.get("buildcostmetal", "0"), fields.get("buildcostenergy", "0")]

func place_structure(type: String, point: Vector2) -> bool:
	if mobile.speed != 0:
		status_label.text = "  Wait for Commander to stop before placing"
		return false
	var id: int = economy.begin_build(type, point)
	if id == 0:
		status_label.text = "  " + economy.status
		return false
	placement_type = ""
	var unit: Dictionary = economy.units[id]
	var sprite := Sprite2D.new()
	sprite.texture = structure_texture(type, id)
	sprite.position = unit.position
	sprite.scale = Vector2.ONE * (0.28 * 192.0 / 55.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(sprite)
	structure_sprites[id] = sprite
	var footprint: Rect2 = economy.footprint(type, unit.position)
	for y in range(maxi(0, int(footprint.position.y / 16) - 1), mini(navigation.height, int(ceil(footprint.end.y / 16)) + 2)):
		for x in range(maxi(0, int(footprint.position.x / 16) - 1), mini(navigation.width, int(ceil(footprint.end.x / 16)) + 2)):
			if footprint.intersects(Rect2(Vector2(x * 16 - 16, y * 16 - 16), Vector2(32, 32))):
				navigation.blocked[y * navigation.width + x] = 1
	if not building:
		toggle_build()
	return true

func structure_texture(type: String, id: int) -> Texture2D:
	var key := str(id) if economy.scripts.has(id) else type
	if structure_views.has(key):
		return structure_views[key].get_texture()
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var model: Node3D = unit_visuals.instantiate(type)
	view.add_child(model)
	if economy.scripts.has(id):
		structure_models[id] = model
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 192
	camera.position = Vector3(0, 130, 180)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	structure_views[key] = view
	return view.get_texture()

func build_model() -> void:
	model_view = SubViewport.new()
	model_view.size = Vector2i(256, 256)
	model_view.transparent_bg = true
	model_view.own_world_3d = true
	model_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(model_view)
	unit_catalog = UnitCatalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	assert(unit_catalog.fault.is_empty(), unit_catalog.fault)
	unit_visuals = UnitVisuals.new(unit_catalog)
	model_root = unit_visuals.instantiate("armcom")
	model_view.add_child(model_root)
	piece_nodes.assign(model_root.get_meta("pieces"))
	rig_nodes = model_root.get_meta("rig")
	rig_origins = model_root.get_meta("origins")
	var max_y := 0.0
	var min_y := 0.0
	for index in range(unit_data.pieces.size()):
		for vertex: Array in unit_data.pieces[index].vertices:
			var p := piece_nodes[index].global_position + ta_vector(vertex)
			max_y = maxf(max_y, p.y)
			min_y = minf(min_y, p.y)
	var camera := Camera3D.new()
	model_view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(55.0, (max_y - min_y) * 1.6)
	camera.far = 1000
	var target := Vector3(0, (min_y + max_y) * 0.5, 0)
	camera.position = target + Vector3(0, 130, 180)
	camera.look_at(target)
	camera.current = true

func start_script_runtime() -> void:
	var path := assets.path_join("armcom.cob.json")
	if not FileAccess.file_exists(path):
		status_label.text = "  Missing COB data. Run python tools/prepare_viewer.py."
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	script_vm = CobVM.new(data)
	script_vm.invoke("Create")
	apply_script_pose()
	if "--walk" in OS.get_cmdline_user_args() or "--record" in OS.get_cmdline_user_args():
		toggle_walk()

func apply_script_pose() -> void:
	if script_vm == null:
		return
	for piece: Dictionary in script_vm.pieces:
		var key := String(piece.name).to_lower()
		if not rig_nodes.has(key):
			push_error("COB model piece is missing: " + key)
			continue
		var node: Node3D = rig_nodes[key]
		node.position = rig_origins[key] + ta_vector(piece.position)
		var angle := Vector3(float(piece.rotation[0]), float(piece.rotation[1]), float(piece.rotation[2])) * TAU / 65536.0
		# Reflect TA's model Z axis into Godot. Rotation-order fidelity remains under review.
		node.rotation = Vector3(-angle.x, -angle.y, angle.z)
		node.visible = bool(piece.visible)
	if script_label != null:
		script_label.text = "Script tick %d  ·  %d / 8 threads" % [script_vm.ticks, script_vm.active_threads()]
	if not script_vm.fault.is_empty():
		status_label.text = "  SCRIPT STOPPED: " + script_vm.fault
		status_label.add_theme_color_override("font_color", Color("ff8888"))

func toggle_walk() -> void:
	if script_vm == null or not script_vm.fault.is_empty():
		return
	if mobile != null and (not mobile.route.is_empty() or mobile.speed != 0):
		stop_order()
		return
	walking = not walking
	script_vm.invoke("StartMoving" if walking else "StopMoving")
	walk_button.text = "Stop walking  [Space]" if walking else "Play walk cycle  [Space]"
	status_label.text = "  Original COB walk cycle — preview stays in place" if walking else "  Original StopMoving callback — settling pose"
	apply_script_pose()

func aim_and_fire(tertiary := false) -> void:
	if script_vm == null or not script_vm.fault.is_empty():
		return
	if building:
		toggle_build()
	var callback := "AimTertiary" if tertiary else "AimPrimary"
	var id: int = script_vm.invoke(callback, [-8192 if tertiary else 8192, 0])
	pending_shot = {"id": id, "callback": "FireTertiary" if tertiary else "FirePrimary"}
	status_label.text = "  %s — waiting for the script's aim-complete result" % callback
	apply_script_pose()

func clear_target() -> void:
	if script_vm == null or not script_vm.fault.is_empty():
		return
	pending_shot.clear()
	if building:
		toggle_build()
	else:
		script_vm.invoke("TargetCleared", [0])
	status_label.text = "  Original restore routine — returning from aim"

func toggle_build() -> void:
	if script_vm == null or not script_vm.fault.is_empty():
		return
	pending_shot.clear()
	building = not building
	if building:
		var restore_id: int = script_vm.invoke("TargetCleared", [0])
		# Complete the restore before launching construction; avoids overlapping routines.
		set_meta("pending_build", restore_id)
	else:
		set_meta("pending_build", -1)
		script_vm.invoke("StopBuilding")
	build_button.text = "Leave build pose  [B]" if building else "Preview build pose  [B]"
	status_label.text = "  Original Commander construction pose"

func step_script() -> void:
	if script_vm == null or not script_vm.fault.is_empty():
		return
	script_vm.step()
	if mobile != null:
		var was_active: bool = not mobile.route.is_empty() or mobile.speed != 0
		mobile.step()
		unit_position = mobile.point()
		if was_active or not mobile.callbacks.is_empty():
			heading = -float(mobile.heading) * TAU / 65536.0
			model_root.rotation.y = heading
			status_label.text = "  %s  ·  (%d, %d)  ·  speed %.2f" % [mobile.status, unit_position.x, unit_position.y, mobile.speed / 65536.0]
		if mobile.route.is_empty():
			route_line.clear_points()
		update_world()
	if economy != null:
		economy.units[economy.builder_id].position = unit_position
		economy.builder_ready = mobile.speed == 0 and script_vm.values.get(5, 0) == 1
		var was_building: bool = economy.task_id != 0
		economy.step()
		resource_label.text = "Metal %.0f / %.0f\nEnergy %.0f / %.0f" % [economy.metal, economy.metal_storage, economy.energy, economy.energy_storage]
		for id: int in structure_sprites:
			var remaining := float(economy.units[id].remaining)
			structure_sprites[id].modulate = Color(1, 1, 1, 0.25 + 0.75 * (1.0 - remaining))
			if structure_models.has(id):
				UnitVisuals.apply_pose(structure_models[id], economy.scripts[id].pieces)
		if was_building:
			status_label.text = "  " + economy.status
		if not economy.completed.is_empty() and building:
			toggle_build()
			status_label.text = "  Construction complete"
	var restore_id := int(get_meta("pending_build", -1))
	if restore_id >= 0 and script_vm.completions.has(restore_id):
		set_meta("pending_build", -1)
		if script_vm.completions[restore_id].reason == "return":
			var build_angle := 4096
			if economy != null and economy.task_id != 0:
				var target: Vector2 = economy.units[economy.task_id].position
				build_angle = roundi(atan2(unit_position.x - target.x, unit_position.y - target.y) * 65536.0 / TAU) - mobile.heading
			script_vm.invoke("StartBuilding", [build_angle, 0])
	if not pending_shot.is_empty() and script_vm.completions.has(int(pending_shot.id)):
		var result: Dictionary = script_vm.completions[int(pending_shot.id)]
		if result.reason == "return" and int(result.result) == 1:
			script_vm.invoke(pending_shot.callback)
			status_label.text = "  Aim completed → original muzzle flash (no projectile simulation)"
		elif result.reason == "return":
			status_label.text = "  Aim declined by the original script; clear target before changing weapons"
		pending_shot.clear()
	apply_script_pose()

func ta_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), -float(value[2])) / 65536.0

func build_interface() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var header := PanelContainer.new()
	header.custom_minimum_size.y = 86
	root.add_child(header)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 28)
	header_margin.add_theme_constant_override("margin_right", 28)
	header.add_child(header_margin)
	var header_row := HBoxContainer.new()
	header_margin.add_child(header_row)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_box)
	title_box.add_child(label("TOTAL ANNIHILATION", 27, Color("e9eee4")))
	title_box.add_child(label("RECONSTRUCTION  /  MOVEMENT & CONSTRUCTION", 12, Color("a6b98d")))
	header_row.add_child(label("BUILD ORDERS   •   RESOURCE ECONOMY", 12, Color("b7bdab")))
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 0)
	root.add_child(middle)
	map_panel = Control.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.clip_contents = true
	middle.add_child(map_panel)
	map_panel.gui_input.connect(map_input)
	map_panel.resized.connect(update_world)
	world = Node2D.new()
	map_panel.add_child(world)
	terrain_sprite = Sprite2D.new()
	terrain_sprite.texture = terrain
	terrain_sprite.centered = false
	terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(terrain_sprite)
	route_line = Line2D.new()
	route_line.width = 1.4
	route_line.default_color = Color("82d9c7")
	world.add_child(route_line)
	selection = Line2D.new()
	selection.width = 1.2
	selection.default_color = Color("d2ee8c")
	for i in range(49):
		var a := i * TAU / 48.0
		selection.add_point(Vector2(cos(a) * 19, sin(a) * 9))
	world.add_child(selection)
	unit_sprite = Sprite2D.new()
	unit_sprite.texture = model_view.get_texture()
	unit_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	unit_sprite.scale = Vector2(0.28, 0.28)
	world.add_child(unit_sprite)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 310
	middle.add_child(sidebar)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	scroll.add_child(margin)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(label("COMET CATCHER", 21, Color("edf0e8")))
	column.add_child(label("6,144 × 7,680  ·  Original terrain tiles", 12))
	var preview := TextureRect.new()
	preview.texture = model_view.get_texture()
	preview.custom_minimum_size = Vector2(230, 150)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(preview)
	column.add_child(label("ARM COMMANDER", 20, Color("d5e4ac")))
	column.add_child(label("Original geometry, textures & script", 13))
	resource_label = label("Metal 1000\nEnergy 1000", 14, Color("d5e4ac"))
	column.add_child(resource_label)
	build_picker = OptionButton.new()
	for type: String in unit_catalog.build_options("armcom"):
		build_picker.add_item(unit_catalog.definition(type).get("name", type))
		build_picker.set_item_metadata(build_picker.item_count - 1, type)
	column.add_child(build_picker)
	column.add_child(button("Place selected structure", choose_build))
	column.add_child(label("Click terrain to move · Right-click / S to stop", 11))
	column.add_child(button("Stop movement  [S]", stop_order))
	walk_button = button("Play walk cycle  [Space]", toggle_walk)
	column.add_child(walk_button)
	var weapons := HBoxContainer.new()
	column.add_child(weapons)
	for item: Array in [["Aim + flash  [1]", false], ["D-gun pose  [2]", true]]:
		var tertiary: bool = item[1]
		var control := button(item[0], func() -> void: aim_and_fire(tertiary))
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weapons.add_child(control)
	column.add_child(button("Clear target  [C]", clear_target))
	build_button = button("Preview build pose  [B]", toggle_build)
	column.add_child(build_button)
	var rotation_row := HBoxContainer.new()
	column.add_child(rotation_row)
	for direction in [-1, 1]:
		var control := button("Turn left  [Q]" if direction < 0 else "Turn right  [E]", func() -> void: rotate_unit(direction * PI / 4))
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotation_row.add_child(control)
	column.add_child(button("Center on commander  [F]", center_unit))
	var map_controls := HBoxContainer.new()
	column.add_child(map_controls)
	var full_map := button("Full map", fit_map)
	full_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_controls.add_child(full_map)
	var reset := button("Reset zoom  [R]", reset_view)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_controls.add_child(reset)
	zoom_label = label("", 13, Color("b3c18e"))
	column.add_child(zoom_label)
	script_label = label("", 12, Color("b3c18e"))
	column.add_child(script_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(label("Drag to pan · Scroll to zoom\nClick terrain to move commander", 13))
	var note := label("Development build · Movement & construction\nClick a finished solar collector to toggle power.", 12, Color("a1aba9"))
	column.add_child(note)
	var footer := PanelContainer.new()
	footer.custom_minimum_size.y = 34
	root.add_child(footer)
	status_label = label("  Loaded from your local game installation", 12)
	footer.add_child(status_label)

func update_world() -> void:
	if world == null or map_panel == null:
		return
	world.scale = Vector2(map_zoom, map_zoom)
	world.position = map_panel.size * 0.5 - map_center * map_zoom
	selection.position = unit_position + Vector2(0, 15)
	unit_sprite.position = unit_position
	if zoom_label != null:
		zoom_label.text = "Zoom  %d%%" % roundi(map_zoom * 100)

func rotate_unit(amount: float) -> void:
	heading += amount
	model_root.rotation.y = heading
	if mobile != null:
		mobile.heading = roundi(-heading * 65536.0 / TAU) & 65535

func center_unit() -> void:
	map_center = unit_position
	update_world()

func fit_map() -> void:
	map_zoom = minf(map_panel.size.x / float(scene_data.width), map_panel.size.y / float(scene_data.height))
	map_center = Vector2(float(scene_data.width), float(scene_data.height)) * 0.5
	update_world()

func reset_view() -> void:
	map_zoom = 1.4
	center_unit()

func map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				set_meta("press_position", event.position)
			elif event.position.distance_to(get_meta("press_position", event.position)) < 5:
				var pos: Vector2 = (event.position - world.position) / map_zoom
				if not placement_type.is_empty():
					place_structure(placement_type, pos)
				else:
					var resumed := false
					for id: int in structure_sprites:
						var unit: Dictionary = economy.units[id]
						if economy.footprint(unit.type, unit.position).has_point(pos) and economy.set_active(id, not bool(unit.active)):
							status_label.text = "  Solar collector " + ("on" if unit.active else "off")
							resumed = true
							break
						if economy.footprint(unit.type, unit.position).has_point(pos) and economy.resume_build(id):
							mobile.stop()
							if not building:
								toggle_build()
							resumed = true
							break
					if not resumed:
						issue_move(pos)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			stop_order()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector2 = (event.position - world.position) / map_zoom
			var factor := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			map_zoom = clampf(map_zoom * factor, 0.04, 8.0)
			map_center = before - (event.position - map_panel.size * 0.5) / map_zoom
	elif event is InputEventMouseMotion and dragging:
		map_center -= event.relative / map_zoom
	update_world()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or world == null:
		return
	if event.keycode == KEY_Q:
		rotate_unit(-PI / 4)
	elif event.keycode == KEY_E:
		rotate_unit(PI / 4)
	elif event.keycode == KEY_F:
		center_unit()
	elif event.keycode == KEY_R:
		reset_view()
	elif event.keycode == KEY_SPACE:
		toggle_walk()
	elif event.keycode == KEY_S:
		stop_order()
	elif event.keycode == KEY_1:
		aim_and_fire()
	elif event.keycode == KEY_2:
		aim_and_fire(true)
	elif event.keycode == KEY_C:
		clear_target()
	elif event.keycode == KEY_B:
		toggle_build()

func _process(delta: float) -> void:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if not playback_paused:
		if "--record" in args or "--capture" in args:
			step_script()
		else:
			tick_accumulator += minf(delta, 0.25)
			while tick_accumulator >= 1.0 / 30.0:
				tick_accumulator -= 1.0 / 30.0
				step_script()
	if frames == 8 and "--verify" in args:
		if world == null or piece_nodes.size() != 15 or terrain.get_width() != 6144:
			get_tree().quit(1)
			return
		rotate_unit(PI / 4)
		assert(is_equal_approx(model_root.rotation.y, PI / 4))
		rotate_unit(-PI / 4)
		fit_map()
		assert(map_zoom < 0.2)
		reset_view()
		assert(is_equal_approx(map_zoom, 1.4))
		assert(script_vm != null and script_vm.fault.is_empty())
		assert(not rig_nodes["lfirept"].visible)
		toggle_walk()
		for _tick in range(10):
			step_script()
		assert(not rig_nodes["lthigh"].rotation.is_zero_approx())
		toggle_walk()
		for _tick in range(100):
			step_script()
		assert(is_zero_approx(rig_nodes["lthigh"].rotation.x))
		aim_and_fire()
		for _tick in range(120):
			step_script()
			if pending_shot.is_empty():
				break
		assert(pending_shot.is_empty() and rig_nodes["lfirept"].visible)
		for _tick in range(3):
			step_script()
		assert(not rig_nodes["lfirept"].visible)
		toggle_build()
		for _tick in range(120):
			step_script()
		assert(script_vm.values.get(5, 0) == 1)
		toggle_build()
		for _tick in range(120):
			step_script()
		assert(script_vm.values.get(5, -1) == 0 and script_vm.statics[1] == 0)
		assert(script_vm.fault.is_empty())
		var start_position := unit_position
		var destination: Vector2 = navigation.nearest_open(start_position + Vector2(128, -96))
		assert(issue_move(destination))
		for _tick in range(1200):
			step_script()
		assert(unit_position.distance_to(destination) < 3.0, "Real-map move must arrive: " + str(unit_position))
		assert(mobile.speed == 0 and mobile.route.is_empty())
		assert(script_vm.fault.is_empty() and script_vm.statics[1] == 0)
		assert(is_zero_approx(rig_nodes["lthigh"].rotation.x))
		print("MOVEMENT_VERIFY_OK start=%s end=%s" % [start_position, unit_position])
		assert(place_structure("armsolar", unit_position + Vector2(80, 0)), economy.status)
		var built_id: int = economy.task_id
		for _tick in range(600):
			step_script()
		assert(economy.units[built_id].remaining == 0 and economy.task_id == 0)
		assert(not building and script_vm.fault.is_empty())
		assert(structure_sprites[built_id].modulate.a == 1.0)
		assert(economy.metal >= 0 and economy.energy >= 0)
		assert(economy.scripts[built_id].fault.is_empty())
		assert(economy.scripts[built_id].values.get(20) == 0)
		assert(economy.set_active(built_id, false))
		for _tick in range(100):
			step_script()
		assert(economy.scripts[built_id].values.get(20) == 1)
		assert(economy.set_active(built_id, true))
		for _tick in range(100):
			step_script()
		assert(economy.scripts[built_id].values.get(20) == 0)
		print("CONSTRUCTION_VERIFY_OK structure=armsolar id=%d" % built_id)
		print("VIEWER_VERIFY_OK")
		get_tree().quit()
	if frames == 20 and "--capture" in args:
		var index := args.find("--capture")
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var result := image.save_png(args[index + 1])
		print("VIEWER_CAPTURE ", result)
		get_tree().quit(0 if result == OK else 1)
	if "--record" in args and frames <= 60:
		var index := args.find("--record")
		var folder := args[index + 1]
		DirAccess.make_dir_recursive_absolute(folder)
		await RenderingServer.frame_post_draw
		var result := get_viewport().get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % frames))
		if result != OK:
			get_tree().quit(1)
		if frames == 60:
			print("VIEWER_RECORD_OK ticks=", script_vm.ticks)
			get_tree().quit()
