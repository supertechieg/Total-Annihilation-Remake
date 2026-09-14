extends Control
## Original assets and COB, with a first controllable ground-movement slice.

const ASSET_RELATIVE = "../local/viewer-assets/"
const CobVM = preload("res://cob_vm.gd")
const UnitCatalog = preload("res://unit_catalog.gd")
const UnitVisuals = preload("res://unit_visuals.gd")
const FeatureAnimation = preload("res://feature_animation.gd")
var unit_catalog: RefCounted
var unit_visuals: RefCounted
const Navigation = preload("res://terrain_navigation.gd")
const MobileUnit = preload("res://mobile_unit.gd")
const ConstructionWorld = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const CombatOverlay = preload("res://combat_overlay.gd")
const WeaponAudio = preload("res://weapon_audio.gd")
var weapon_audio: Node
const Opponent = preload("res://opponent.gd")
const ScenarioResult = preload("res://scenario_result.gd")
const DGUN_MODE := "__dgun__"
const GROUND_ATTACK_MODE := "__ground__"
const CORE_DUEL_UNITS :=["corthud", "corlevlr", "corstorm", "cormist", "corcrash", "corfav", "corgator", "corak"]
var scenario_result: RefCounted
var opponent: RefCounted
var combat: RefCounted
var combat_overlay: Node2D
var economy: RefCounted
var build_picker: OptionButton
var place_button: Button
var selection_label: Label
var resource_label: Label
var placement_type := ""
var structure_sprites: Dictionary = {}
## Wreck and other modelled feature sprites keyed by anchor cell.
var feature_sprites: Dictionary = {}
var feature_sprite_revision := -1
## Shared per-type animation states for animating 2D features: name -> {state, durations, loop, frames, sprites}.
var feature_animations: Dictionary = {}
var feature_layers: Array = []
const Minimap = preload("res://minimap.gd")
var minimap: Control
var structure_views: Dictionary = {}
var structure_models: Dictionary = {}
var selected_unit := 0
var selected_group: Array[int] = []
var box_start := Vector2.INF
var factory_picker: OptionButton
var factory_controls: VBoxContainer
var factory_label: Label
var navigation: RefCounted
var mobile: RefCounted
var route_line: Line2D
var assets: String
var scene_data: Dictionary
var unit_data: Dictionary
var faction := "arm"
var commander_type := "armcom"
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
var map_slug := ""
var map_assets: String

func resolve_faction() -> String:
	var tree := get_tree()
	if tree != null and tree.has_meta("faction"):
		return str(tree.get_meta("faction"))
	var args := OS.get_cmdline_user_args()
	if "--core-factory-demo" in args or "--core-builder-demo" in args:
		return "core"
	for core_unit in CORE_DUEL_UNITS:
		if "--verify-" + core_unit in args:
			return "core"
	if duel_unit().begins_with("cor"):
		return "core"
	var index := args.find("--faction")
	if index >= 0 and index + 1 < args.size():
		var value := String(args[index + 1]).to_lower()
		if value == "core" or value == "arm":
			return value
	return "arm"

static func duel_unit() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--duel-unit")
	return String(args[index + 1]).to_lower() if index >= 0 and index + 1 < args.size() else "armflash"

## Selected skirmish map: tree meta (set by the map picker), then --map <slug>; empty means the bundled Comet Catcher.
func resolve_map() -> String:
	var tree := get_tree()
	if tree != null and tree.has_meta("map"):
		return str(tree.get_meta("map"))
	var args := OS.get_cmdline_user_args()
	var index := args.find("--map")
	return String(args[index + 1]).to_lower() if index >= 0 and index + 1 < args.size() else ""

func switch_map(slug: String) -> void:
	get_tree().set_meta("map", slug)
	get_tree().reload_current_scene()

## Skirmish map selection from local/maps/index.json (prepared by tools/prepare_maps.py); picking one reloads the scene.
func build_map_picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("Comet Catcher (bundled demo)")
	picker.set_item_metadata(0, "")
	var index = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../local/maps/index.json")))
	if index is Dictionary:
		for entry: Dictionary in index.get("maps", []):
			if not bool(entry.get("supported", false)):
				continue
			picker.add_item("%s  ·  %s players" % [entry.name, str(entry.get("players", "?"))])
			picker.set_item_metadata(picker.item_count - 1, entry.slug)
			if entry.slug == map_slug:
				picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(item: int) -> void:
		if str(picker.get_item_metadata(item)) != map_slug:
			switch_map(str(picker.get_item_metadata(item))))
	return picker

func switch_faction(target: String) -> void:
	if target == faction:
		return
	get_tree().set_meta("faction", target)
	get_tree().reload_current_scene()

func image_texture(filename: String, folder := "") -> ImageTexture:
	var image := Image.load_from_file((assets if folder.is_empty() else folder).path_join(filename))
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
	faction = resolve_faction()
	commander_type = "corcom" if faction == "core" else "armcom"
	if not FileAccess.file_exists(assets.path_join("scene.json")) or not FileAccess.file_exists(ProjectSettings.globalize_path("res://../local/unit-assets/index.json")):
		var message := label("Run 'Run Viewer.cmd' to prepare the original map and unit assets.", 22)
		message.position = Vector2(40, 40)
		add_child(message)
		push_error(message.text)
		if "--verify" in OS.get_cmdline_user_args():
			get_tree().quit(1)
		return
	map_slug = resolve_map()
	map_assets = assets
	if not map_slug.is_empty():
		var folder := ProjectSettings.globalize_path("res://../local/maps/").path_join(map_slug).simplify_path()
		if FileAccess.file_exists(folder.path_join("scene.json")):
			map_assets = folder
		else:
			push_error("Map bundle not prepared: " + map_slug + " (run tools/prepare_maps.py)")
			map_slug = ""
	scene_data = JSON.parse_string(FileAccess.get_file_as_string(map_assets.path_join("scene.json")))
	unit_data = JSON.parse_string(FileAccess.get_file_as_string(assets.path_join("unit.json")))
	terrain = image_texture("terrain.png", map_assets)
	# Player 1 starts at the map's first OTA start position; the bundled Comet Catcher keeps its fixed demo point.
	var starts: Array = scene_data.get("start_positions", [])
	if not starts.is_empty():
		unit_position = Vector2(float(starts[0].x), float(starts[0].z))
	build_model()
	build_interface()
	start_script_runtime()
	start_world_movement()
	update_world()
	var commander_unit: Dictionary = unit_catalog.load_unit(commander_type)
	var commander_model: Dictionary = commander_unit.get("model", {})
	print("VIEWER_READY map=%s commander=%s pieces=%d textures=%d" % [scene_data.name, commander_type, int(commander_model.get("pieces", []).size()), int(commander_model.get("textures", {}).size())])

func start_world_movement() -> void:
	var fields: Dictionary = unit_catalog.definition(commander_type)
	if fields.is_empty():
		push_error("Missing commander definition: " + commander_type)
		get_tree().quit(1)
		return
	var terrain_fields: Dictionary = unit_catalog.movement(commander_type)
	var feature_blocking := FileAccess.get_file_as_bytes(map_assets.path_join("features.bin"))
	if feature_blocking.size() != int(scene_data.height_grid_width) * int(scene_data.height_grid_height):
		push_error("Prepare the map feature-blocking bundle with tools/prepare_map_metal.py")
		get_tree().quit(1)
		return
	navigation = Navigation.new(int(scene_data.height_grid_width), int(scene_data.height_grid_height),
		FileAccess.get_file_as_bytes(map_assets.path_join("heights.bin")), int(scene_data.sea_level),
		int(terrain_fields.get("maxslope", 255)), int(terrain_fields.get("maxwaterdepth", 10000)),
		Vector2i(int(terrain_fields.get("footprintx", 2)), int(terrain_fields.get("footprintz", 2))),
		int(terrain_fields.get("minwaterdepth", -10000)), int(terrain_fields.get("maxwaterslope", 255)), feature_blocking)
	unit_position = navigation.nearest_open(unit_position)
	assert(unit_position.x >= 0, "Map has no passable starting point")
	mobile = MobileUnit.new(navigation, fields, unit_position, script_vm)
	economy = ConstructionWorld.new(unit_catalog, navigation, unit_position, commander_type)
	if not economy.set_terrain_metal(FileAccess.get_file_as_bytes(map_assets.path_join("metal.bin"))):
		push_error("Prepare the map metal bundle with tools/prepare_map_metal.py")
		get_tree().quit(1)
		return
	var metal_metadata = JSON.parse_string(FileAccess.get_file_as_string(map_assets.path_join("metal.json")))
	if metal_metadata is Dictionary:
		economy.load_map_features(metal_metadata.get("placements", []), metal_metadata.get("voids", []))
		prime_feature_animations()
	combat = Combat.new(economy)
	# The viewer steps the Commander's script and movement; combat and targeting use them through the world.
	economy.attach_external(economy.builder_id, script_vm, mobile)
	combat.enable_guard(economy.builder_id, false)
	var environment: Dictionary = scene_data.get("environment", {})
	economy.tidal_strength = float(environment.get("tidal_strength", 0.0))
	economy.configure_wind(int(environment.get("min_wind", 100)), int(environment.get("max_wind", 2000)))
	weapon_audio = WeaponAudio.new()
	add_child(weapon_audio)
	combat.sound_requested.connect(weapon_audio.play_sound)
	combat.gravity = int(scene_data.get("environment", {}).get("gravity_raw_per_tick", 8155))
	combat_overlay = CombatOverlay.new()
	combat_overlay.combat = combat
	combat_overlay.z_index = 10
	world.add_child(combat_overlay)
	map_center = unit_position
	if "--verify-wreckage" in OS.get_cmdline_user_args():
		if not run_wreckage_demo():
			push_error("Wreckage scenario failed")
			get_tree().quit(1)
	if "--verify-squads" in OS.get_cmdline_user_args():
		if not run_squad_demo():
			push_error("Squad scenario failed")
			get_tree().quit(1)
	if "--verify-ground-attack" in OS.get_cmdline_user_args():
		if not run_ground_attack_demo():
			push_error("Ground attack scenario failed")
			get_tree().quit(1)
	if "--verify-self-destruct" in OS.get_cmdline_user_args():
		if not run_self_destruct_demo():
			push_error("Self-destruct scenario failed")
			get_tree().quit(1)
	if "--verify-map-features" in OS.get_cmdline_user_args():
		if not run_map_features_demo():
			push_error("Map features scenario failed")
			get_tree().quit(1)
	if "--verify-feature-damage" in OS.get_cmdline_user_args():
		if not run_feature_damage_demo():
			push_error("Feature damage scenario failed")
			get_tree().quit(1)
	if "--verify-reclaim" in OS.get_cmdline_user_args():
		if not run_reclaim_demo():
			push_error("Reclaim scenario failed")
			get_tree().quit(1)
	if "--verify-group-orders" in OS.get_cmdline_user_args():
		if not run_group_orders():
			push_error("Group order scenario failed")
			get_tree().quit(1)
	if "--verify-dgun" in OS.get_cmdline_user_args():
		if not run_dgun_demo():
			push_error("D-gun scenario failed")
			get_tree().quit(1)
	if "--verify-commander-combat" in OS.get_cmdline_user_args():
		if not run_commander_combat():
			push_error("Commander combat scenario failed")
			get_tree().quit(1)
	if "--verify-skirmish-start" in OS.get_cmdline_user_args():
		if not run_skirmish_start():
			push_error("Skirmish start scenario failed")
			get_tree().quit(1)
	if "--verify-opponent" in OS.get_cmdline_user_args():
		start_opponent()
		var initial_health: int = economy.units[economy.builder_id].health
		for tick in range(6500):
			step_script()
			if not economy.units.has(economy.builder_id) or int(economy.units[economy.builder_id].health) < initial_health:
				break
		if opponent == null or opponent.structures_started < 2 or opponent.attacks == 0 or (economy.units.has(economy.builder_id) and int(economy.units[economy.builder_id].health) == initial_health):
			printerr("Opponent scenario: opponent=%s started=%d attacks=%d queued=%d health=%s/%d" % [opponent != null, opponent.structures_started if opponent != null else -1, opponent.attacks if opponent != null else -1, opponent.queued if opponent != null else -1, economy.units[economy.builder_id].health if economy.units.has(economy.builder_id) else "dead", initial_health])
			push_error("Opponent scenario failed")
			get_tree().quit(1)
		else:
			print("OPPONENT_VIEWER_OK constructed base, produced units and damaged Commander")
			for id: int in economy.units.keys():
				if int(economy.units[id].get("team", 0)) == 1:
					economy.remove_unit(id)
			check_scenario_result()
			var finished_tick: int = economy.ticks
			step_script()
			if scenario_result.outcome != "victory" or economy.ticks != finished_tick:
				push_error("Opponent result/freeze failed")
				get_tree().quit(1)
			else:
				print("OPPONENT_RESULT_OK victory latched and simulation stopped")
	if "--move" in OS.get_cmdline_user_args():
		issue_move(unit_position + Vector2(128, -96))
	if "--construction-demo" in OS.get_cmdline_user_args():
		place_structure("armsolar", unit_position + Vector2(80, 0))
		for tick in range(600):
			step_script()
	if "--factory-demo" in OS.get_cmdline_user_args():
		assert(run_factory_demo(), "Factory demo failed")
	if "--kbot-demo" in OS.get_cmdline_user_args():
		if not run_factory_demo("armlab", "armpw"):
			push_error("Kbot demo failed")
			get_tree().quit(1)
	if "--core-factory-demo" in OS.get_cmdline_user_args():
		if not run_core_factory_demo():
			push_error("Core factory demo failed")
			get_tree().quit(1)
	if "--builder-demo" in OS.get_cmdline_user_args() or "--core-builder-demo" in OS.get_cmdline_user_args():
		if not run_builder_demo():
			push_error("Mobile builder demo failed")
			get_tree().quit(1)
	if "--combat-demo" in OS.get_cmdline_user_args() or "--verify-combat" in OS.get_cmdline_user_args():
		if not run_combat_demo("--verify-combat" in OS.get_cmdline_user_args()):
			push_error("Combat demo failed")
			get_tree().quit(1)
	if "--duel-demo" in OS.get_cmdline_user_args() or "--verify-duel" in OS.get_cmdline_user_args():
		if not run_duel_demo("--verify-duel" in OS.get_cmdline_user_args(), duel_unit()):
			push_error("Tank duel failed")
			get_tree().quit(1)
	if "--verify-stumpy" in OS.get_cmdline_user_args():
		if not run_duel_demo(true, "armstump"):
			push_error("Stumpy duel failed")
			get_tree().quit(1)
	for missile_unit in ["armsam", "armjeth"]:
		if "--verify-" + missile_unit in OS.get_cmdline_user_args():
			if not run_duel_demo(true, missile_unit):
				push_error("Missile duel failed: " + missile_unit)
				get_tree().quit(1)
	if "--verify-armfav" in OS.get_cmdline_user_args():
		if not run_duel_demo(true, "armfav"):
			push_error("Jeffy laser duel failed")
			get_tree().quit(1)
	for core_unit in CORE_DUEL_UNITS:
		if "--verify-" + core_unit in OS.get_cmdline_user_args():
			# The original executable's own Thud shots pass over a Raider at 128 (native-cannon-launch-validation.json); see CORE_COMBAT.md.
			if not run_duel_demo(true, core_unit, 192.0 if core_unit == "corthud" else 128.0):
				push_error("Core duel failed: " + core_unit)
				get_tree().quit(1)
	if "--verify-warrior" in OS.get_cmdline_user_args():
		if not run_duel_demo(true, "armwar"):
			push_error("Warrior duel failed")
			get_tree().quit(1)
	if "--verify-rocko" in OS.get_cmdline_user_args():
		if not run_duel_demo(true, "armrock"):
			get_tree().quit(1)
			return
	if "--verify-peewee" in OS.get_cmdline_user_args():
		if not run_duel_demo(true, "armpw"):
			push_error("Peewee duel failed")
			get_tree().quit(1)
	if "--verify-hammer" in OS.get_cmdline_user_args():
		if not run_duel_demo(true, "armham"):
			push_error("Hammer duel failed")
			get_tree().quit(1)

func run_duel_demo(verify: bool, player_type := "armflash", standoff := 128.0) -> bool:
	var factory_type := ""
	for candidate: String in ConstructionWorld.GROUND_FACTORIES:
		if player_type in unit_catalog.build_options(candidate) and candidate.begins_with(player_type.substr(0, 3)):
			factory_type = candidate
	if factory_type.is_empty() or not run_factory_demo(factory_type, player_type, 1):
		return false
	var source := 0
	for unit: Dictionary in economy.units.values():
		if unit.type == player_type:
			source = unit.id
			break
	select_unit(source)
	var target := add_practice_target(standoff)
	if target == 0 or not combat.attack(source, target) or not combat.attack(target, source):
		printerr("Duel setup failed: target=", target, " ", combat.status, " ", status_label.text)
		return false
	var source_health: int = economy.units[source].health
	var target_health: int = economy.units[target].health
	for tick in range(1200 if verify else 100):
		step_script()
		if not economy.units.has(source) or not economy.units.has(target):
			break
	if verify:
		if economy.units.has(source) and economy.units.has(target):
			printerr("Duel unresolved: shots=%d hits=%d source_health=%d/%d target_health=%d/%d status=%s faults=%s" % [combat.shots_fired, combat.hits,
				int(economy.units[source].health), source_health, int(economy.units[target].health), target_health, combat.status,
				str(combat.cycles.values().map(func(cycle) -> String: return cycle.fault))])
			return false
		if economy.units.has(source) and int(economy.units[source].health) >= source_health:
			printerr("Duel one-sided: %s survived undamaged; shots=%d hits=%d" % [player_type, combat.shots_fired, combat.hits])
			return false
		if economy.units.has(target) and int(economy.units[target].health) >= target_health:
			printerr("Duel one-sided: target survived undamaged by %s; shots=%d hits=%d status=%s" % [player_type, combat.shots_fired, combat.hits, combat.status])
			return false
		for cycle in combat.cycles.values():
			if not cycle.fault.is_empty():
				printerr("Duel weapon fault: ", cycle.fault)
				return false
		print("DUEL_VERIFY_OK factory-produced %s and armed Raider exchanged damage; one tank destroyed" % player_type)
	return true

func add_practice_target(distance := 128.0) -> int:
	if selected_unit == 0 or not economy.units.has(selected_unit) or economy.units[selected_unit].type not in Combat.SUPPORTED_UNITS:
		status_label.text = "  Select an armed unit with supported weapons to add a practice target"
		return 0
	for direction: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var point: Vector2 = (economy.units[selected_unit].position + direction * distance).snapped(Vector2(16, 16))
		if not navigation.passable(navigation.cell_at(point)):
			continue
		var clear := true
		for unit: Dictionary in economy.units.values():
			if economy.footprint("corraid", point).intersects(economy.footprint(unit.type, unit.position)):
				clear = false
		if not clear:
			continue
		var id: int = economy.add_unit("corraid", point, 0.0)
		economy.units[id].team = 1
		add_structure_sprite(id)
		status_label.text = "  Click the red-ringed target to attack with the selected tank"
		combat_overlay.queue_redraw()
		return id
	status_label.text = "  No clear nearby target location"
	return 0

func add_armed_raider() -> void:
	var raider := add_practice_target()
	if raider != 0:
		combat.enable_guard(raider)
		combat.attack(selected_unit, raider, true)
		status_label.text = "  Raider engages nearby enemies; your tank is attacking"

func run_combat_demo(verify: bool) -> bool:
	if not run_factory_demo():
		return false
	var source := 0
	for unit: Dictionary in economy.units.values():
		if unit.type == "armflash":
			source = unit.id
			break
	select_unit(source)
	var target := add_practice_target()
	if target == 0 or not combat.attack(source, target):
		return false
	for tick in range(100):
		step_script()
	if combat.hits == 0 or combat.shots_fired == 0:
		return false
	if verify:
		for tick in range(1000):
			step_script()
			if not economy.units.has(target):
				break
		if economy.units.has(target) or structure_sprites.has(target) or not combat.cycles[source].fault.is_empty():
			return false
		print("COMBAT_VERIFY_OK factory-produced Flash attacked and destroyed practice target")
	return true

func run_factory_demo(factory_type := "armvp", product_type := "armflash", product_count := 2, side := -1.0) -> bool:
	select_unit(0)
	var offset := float(unit_catalog.movement(factory_type).get("footprintx", "8")) * 8 + 48
	var point := unit_position + Vector2(side * offset, 0)
	if not place_structure(factory_type, point):
		return false
	var id: int = economy.task_id
	for tick in range(1200):
		step_script()
	if float(economy.units[id].remaining) != 0:
		return false
	select_unit(id)
	for index in range(factory_picker.item_count):
		if factory_picker.get_item_metadata(index) == product_type:
			factory_picker.select(index)
	for item in range(product_count):
		queue_factory_unit()
	var production_ticks := ceili(float(unit_catalog.definition(product_type).buildtime) * 30.0 / float(unit_catalog.definition(factory_type).workertime)) * product_count + 900
	for tick in range(production_ticks):
		step_script()
	var produced: Array = []
	for unit: Dictionary in economy.units.values():
		if int(unit.get("produced_by", 0)) == id:
			produced.append(unit.id)
	if produced.size() != product_count or int(economy.factories[id].product) != 0:
		return false
	for product: int in produced:
		if float(economy.units[product].remaining) != 0 or not economy.scripts[product].fault.is_empty():
			return false
	select_unit(int(produced[0]))
	var target: Vector2 = economy.units[produced[0]].position + Vector2(-96, 96)
	if not issue_move(target):
		return false
	for tick in range(500):
		step_script()
	if economy.units[produced[0]].position.distance_to(target) > 5:
		return false
	select_unit(id)
	print("FACTORY_VERIFY_OK built=%s produced=%d %s; exit and selected movement passed" % [factory_type, product_count, product_type])
	return true

## Group control: Shift+drag box select, A selects the army, clicks issue formation moves or group attacks.
func selectable_unit(id: int) -> bool:
	if not economy.units.has(id) or id == economy.builder_id:
		return false
	var unit: Dictionary = economy.units[id]
	return int(unit.get("team", 0)) == 0 and float(unit.remaining) == 0 and economy.mobile_units.has(id)

func select_group(ids: Array) -> int:
	selected_group.clear()
	for id in ids:
		if selectable_unit(int(id)):
			selected_group.append(int(id))
	if selected_group.size() == 1:
		select_unit(selected_group[0])
	elif not selected_group.is_empty():
		select_unit(selected_group[0])
		selection_label.text = "Selected: %d units" % selected_group.size()
	combat_overlay.selected = selected_group.duplicate()
	combat_overlay.queue_redraw()
	return selected_group.size()

func select_group_in_rect(rect: Rect2) -> int:
	var ids: Array = []
	for id: int in economy.units:
		if rect.abs().has_point(economy.units[id].position):
			ids.append(id)
	return select_group(ids)

## Squads (0x48d920 CreateSquad / 0x48d9a0 SelectSquad): the squad number lives on each unit (unit +0xac).
## Creating squad n puts every selected unit in n and moves units that were in n but are not selected to squad 0.
func create_squad(squad: int) -> int:
	var count := 0
	for id: int in economy.units:
		var unit: Dictionary = economy.units[id]
		if int(unit.get("team", 0)) != 0:
			continue
		if id in selected_group:
			unit.squad = squad
			count += 1
		elif int(unit.get("squad", 0)) == squad:
			unit.squad = 0
	status_label.text = "  Squad %d: %d units" % [squad, count]
	return count

## Selecting squad n selects its selectable members; without Shift everything else is deselected, with Shift it adds.
func select_squad(squad: int, add := false) -> int:
	var ids: Array = selected_group.duplicate() if add else []
	for id: int in economy.units:
		if int(economy.units[id].get("squad", 0)) == squad and selectable_unit(id) and not combat.pending_deaths.has(id) and not id in ids:
			ids.append(id)
	var count := select_group(ids)
	status_label.text = "  Selected squad %d: %d units" % [squad, count]
	return count

## Ctrl+Z: add every own selectable unit whose type matches a selected unit's type.
func select_same_types() -> int:
	var types: Array = []
	for id in selected_group:
		if economy.units.has(int(id)):
			types.append(economy.units[int(id)].type)
	var ids: Array = selected_group.duplicate()
	for id: int in economy.units:
		if selectable_unit(id) and economy.units[id].type in types and not id in ids:
			ids.append(id)
	return select_group(ids)

func select_all_own() -> int:
	var ids: Array = []
	for id: int in economy.units:
		if selectable_unit(id):
			ids.append(id)
	return select_group(ids)

func run_squad_demo() -> bool:
	# Ctrl+number assigns, Alt+number selects (Shift adds), dead members drop out, Ctrl+Z adds matching types.
	var type := "armflash" if faction == "arm" else "corraid"
	var ids: Array = []
	for index in range(4):
		var point: Vector2 = navigation.nearest_open(unit_position + Vector2(-240 + index * 60, 200))
		var id: int = economy.add_unit(type if index < 3 else ("armpw" if faction == "arm" else "corak"), point, 0.0, 0)
		economy.mobile_units[id] = MobileUnit.new(economy.unit_navigation(economy.units[id].type), unit_catalog.definition(economy.units[id].type), point, economy.scripts[id])
		add_structure_sprite(id)
		ids.append(id)
	select_group([ids[0], ids[1]])
	if create_squad(2) != 2:
		return false
	select_group([ids[3]])
	create_squad(3)
	select_group([ids[2]])
	if select_squad(2) != 2 or not (ids[0] in selected_group and ids[1] in selected_group) or ids[2] in selected_group:
		printerr("Squad demo: squad 2 selection ", selected_group)
		return false
	if select_squad(3, true) != 3:
		printerr("Squad demo: shift add gave ", selected_group)
		return false
	select_group([ids[1]])
	create_squad(2)
	if int(economy.units[ids[0]].get("squad", 0)) != 0 or select_squad(2) != 1:
		printerr("Squad demo: reassignment left ", economy.units[ids[0]].get("squad", 0))
		return false
	select_group([ids[0]])
	if select_same_types() != 3:
		printerr("Squad demo: Ctrl+Z selected ", selected_group)
		return false
	combat.apply_damage(ids[1], 5000)
	combat.process_deaths()
	if select_squad(2) != 0:
		printerr("Squad demo: dead member still selected")
		return false
	print("SQUADS_VERIFY_OK Ctrl+number assign, Alt+number select, Shift add, reassignment, Ctrl+Z same type and dead-member removal")
	return true

func select_army() -> int:
	var ids: Array = []
	for id: int in economy.units:
		if selectable_unit(id) and economy.units[id].type in Combat.SUPPORTED_UNITS:
			ids.append(id)
	return select_group(ids)

func group_move(point: Vector2) -> int:
	var live: Array = selected_group.filter(func(id: int) -> bool: return economy.units.has(id))
	var columns := maxi(1, ceili(sqrt(float(live.size()))))
	@warning_ignore("integer_division")
	var rows := maxi(1, ceili(float(live.size()) / float(columns)))
	var accepted := 0
	for index in range(live.size()):
		var id: int = live[index]
		var offset := Vector2((index % columns) - (columns - 1) * 0.5, (index / columns) - (rows - 1) * 0.5) * 40.0
		var destination: Vector2 = economy.unit_navigation(economy.units[id].type).nearest_open(point + offset)
		if destination.x >= 0 and economy.move_unit(id, destination):
			combat.stop(id, false)
			accepted += 1
	status_label.text = "  Group move: %d / %d units" % [accepted, live.size()]
	return accepted

func group_attack(target: int) -> int:
	var accepted := 0
	for id: int in selected_group:
		if economy.units.has(id) and combat.attack(id, target, true):
			accepted += 1
	status_label.text = "  Group attack: %d units" % accepted
	return accepted

func spawn_own_unit(type: String, point: Vector2) -> int:
	var id: int = economy.add_unit(type, point, 0.0)
	economy.mobile_units[id] = MobileUnit.new(economy.unit_navigation(type), unit_catalog.definition(type), point, economy.scripts.get(id))
	economy.mobile_units[id].heading = 32768
	add_structure_sprite(id)
	return id

func run_group_orders() -> bool:
	var type: String = Opponent.FACTIONS[faction].vehicle_combat
	var squad: Array = []
	for offset: Vector2 in [Vector2(-40, 0), Vector2(0, 0), Vector2(40, 0), Vector2(0, 40)]:
		var point: Vector2 = navigation.nearest_open(unit_position + Vector2(-240, 160) + offset)
		if point.x < 0:
			return false
		squad.append(spawn_own_unit(type, point))
	var box := Rect2(unit_position + Vector2(-320, 100), Vector2(160, 140))
	if select_group_in_rect(box) != squad.size():
		printerr("Group select found %d of %d" % [selected_group.size(), squad.size()])
		return false
	var destination: Vector2 = navigation.nearest_open(unit_position + Vector2(-240, -200))
	if group_move(destination) != squad.size():
		return false
	for tick in range(1500):
		step_script()
	var positions: Array = squad.map(func(id: int) -> Vector2: return economy.units[id].position)
	for index in range(positions.size()):
		if positions[index].distance_to(destination) > 90:
			printerr("Group move: unit %d ended %s from %s" % [index, positions[index], destination])
			return false
		for other in range(index + 1, positions.size()):
			if positions[index].distance_to(positions[other]) < 16:
				printerr("Group move: units %d and %d overlap" % [index, other])
				return false
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var enemy: int = economy.add_unit(enemy_type, navigation.nearest_open(destination + Vector2(0, -160)), 0.0, 1)
	add_structure_sprite(enemy)
	if group_attack(enemy) != squad.size():
		return false
	for tick in range(1500):
		step_script()
		if not economy.units.has(enemy):
			break
	for id: int in squad:
		if economy.scripts.has(id) and not economy.scripts[id].fault.is_empty():
			return false
	if economy.units.has(enemy):
		printerr("Group attack did not destroy the enemy")
		return false
	print("GROUP_VERIFY_OK box-selected %d %s, formation move and group attack destroyed %s" % [squad.size(), type, enemy_type])
	return true

func run_wreckage_demo() -> bool:
	# Commander lasers kill an adjacent enemy; its wreck must appear as a feature, render and block navigation.
	var map_features: int = economy.features.instances.size()
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var point: Vector2 = navigation.nearest_open(unit_position + Vector2(150, 0))
	var enemy: int = economy.add_unit(enemy_type, point, 0.0, 1)
	add_structure_sprite(enemy)
	var deaths_before: int = combat.deaths.size()
	var started := Time.get_ticks_msec()
	for tick in range(1500):
		step_script()
		if not economy.units.has(enemy):
			break
	if economy.units.has(enemy) or combat.deaths.size() == deaths_before:
		printerr("Wreckage demo: enemy not destroyed")
		return false
	var death: Dictionary = combat.deaths[deaths_before]
	for tick in range(5):
		step_script()
	var anchor := int(death.anchor)
	var wreck_ok: bool = int(death.corpsetype) == 0 or (anchor >= 0 and economy.features.instances.has(anchor))
	var rendered: bool = int(death.corpsetype) == 0 or feature_sprites.has(anchor)
	if not wreck_ok or not rendered:
		printerr("Wreckage demo: corpsetype=%d anchor=%d instance=%s sprite=%s" % [int(death.corpsetype), anchor, economy.features.instances.has(anchor), feature_sprites.has(anchor)])
		return false
	print("WRECKAGE_VERIFY_OK %s died with severity %d, corpse type %d -> %s at cell %d; map features %d; %.1f s" % [enemy_type, int(death.severity), int(death.corpsetype),
		economy.features.instances[anchor].name if anchor >= 0 else "none", anchor, map_features, float(Time.get_ticks_msec() - started) / 1000.0])
	return true

## A click on a reclaimable feature orders the selected builder (or the Commander) to reclaim it.
func reclaim_at(point: Vector2) -> bool:
	if economy == null or point.x < 0 or point.y < 0:
		return false
	var cell := int(point.y / 16) * int(economy.features.width) + int(point.x / 16)
	var anchor: int = economy.features.anchor_of(cell)
	if anchor < 0 or not economy.features.instances.has(anchor) or not bool(unit_catalog.feature(economy.features.instances[anchor].name).get("reclaimable", false)):
		return false
	var source: int = economy.builder_id if selected_unit == 0 else selected_unit
	if not economy.can_reclaim(source):
		return false
	if source == economy.builder_id and building:
		toggle_build()
	var accepted: bool = economy.reclaim(source, cell)
	if accepted and source == economy.builder_id:
		combat.stop(source, false)
		route_line.points = mobile.route
	status_label.text = "  " + economy.status
	return accepted

func run_map_features_demo() -> bool:
	# Every drawable 2D feature has a node at the 0x46a610 anchor, computed here independently from the raw height grid;
	# with --require-animation, animating types must change drawn frames as their GAF durations elapse.
	sync_feature_sprites()
	var width: int = economy.features.width
	var rows: int = economy.features.height
	var heights: PackedByteArray = navigation.heights
	var expected := 0
	for anchor: int in economy.features.instances:
		var name: String = economy.features.instances[anchor].name
		if not unit_catalog.load_feature_model(name).is_empty() or not unit_catalog.feature_sprites(name).has("sprite"):
			continue
		@warning_ignore("integer_division")
		var x := anchor % width
		@warning_ignore("integer_division")
		var z := anchor / width
		if x >= width - 1 or z >= rows - 1:
			if feature_sprites.has(anchor):
				printerr("Map features demo: %s in the last column/row is drawn" % name)
				return false
			continue
		expected += 1
		if not feature_sprites.has(anchor):
			printerr("Map features demo: no sprite for %s at %d" % [name, anchor])
			return false
		var definition: Dictionary = unit_catalog.feature(name)
		var lift := (int(heights[z * width + x]) + int(heights[z * width + x + 1]) + int(heights[(z + 1) * width + x]) + int(heights[(z + 1) * width + x + 1])) >> 3
		var point := Vector2(x * 16 + int(definition.footprintx) * 8, z * 16 + int(definition.footprintz) * 8 - lift)
		if feature_sprites[anchor].position != point:
			printerr("Map features demo: %s drawn at %s, expected %s" % [name, feature_sprites[anchor].position, point])
			return false
	var textures: Dictionary = {}
	for id: String in feature_animations:
		for sprite in feature_animations[id].sprites:
			if is_instance_valid(sprite):
				textures[sprite] = sprite.texture
	for tick in range(90):
		step_script()
	var changed := 0
	for sprite in textures:
		if is_instance_valid(sprite) and sprite.texture != textures[sprite]:
			changed += 1
	var require := "--require-animation" in OS.get_cmdline_user_args()
	if expected == 0 or (require and (feature_animations.is_empty() or changed == 0)):
		printerr("Map features demo: sprites=%d animation states=%d changed sprites=%d" % [expected, feature_animations.size(), changed])
		return false
	print("MAP_FEATURES_VERIFY_OK %s: %d 2D feature sprites at independently computed anchors, %d animation states, %d sprites changed frame over 90 ticks" % [scene_data.name, expected, feature_animations.size(), changed])
	return true

func run_feature_damage_demo() -> bool:
	# The Commander's laser leaves a wreck; a D-gun aimed at an enemy behind it blasts through and destroys the wreck.
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var first: int = economy.add_unit(enemy_type, navigation.nearest_open(unit_position + Vector2(0, 110)), 0.0, 1)
	add_structure_sprite(first)
	var deaths_before: int = combat.deaths.size()
	for tick in range(1500):
		step_script()
		if not economy.units.has(first):
			break
	if economy.units.has(first) or combat.deaths.size() == deaths_before or int(combat.deaths[deaths_before].anchor) < 0:
		printerr("Feature damage demo: no wreck")
		return false
	var anchor := int(combat.deaths[deaths_before].anchor)
	var wreck: String = economy.features.instances[anchor].name
	combat.guards.erase(economy.builder_id)
	var second: int = economy.add_unit(enemy_type, navigation.nearest_open(unit_position + Vector2(0, 220)), 0.0, 1)
	add_structure_sprite(second)
	var destroyed_before: int = combat.feature_destructions
	if not dgun_at(economy.units[second].position):
		printerr("Feature damage demo: D-gun refused: ", combat.status)
		return false
	var shots: int = combat.shots_fired
	for tick in range(600):
		step_script()
		if combat.shots_fired > shots and combat.projectiles.is_empty():
			break
	for tick in range(3):
		step_script()
	var remaining: String = economy.features.instances[anchor].name if economy.features.instances.has(anchor) else "nothing"
	var sprite_ok: bool = not feature_sprites.has(anchor) or str(feature_sprites[anchor].get_meta("feature", "")) == remaining
	if remaining == wreck or combat.feature_destructions == destroyed_before or not sprite_ok or not script_vm.fault.is_empty():
		printerr("Feature damage demo: %s -> %s destructions=%d sprite=%s fault=%s" % [wreck, remaining, combat.feature_destructions - destroyed_before, sprite_ok, script_vm.fault])
		return false
	print("FEATURE_DAMAGE_VERIFY_OK %s D-gun passed over %s (damage %d): %d feature replacements, now %s; enemy destroyed=%s" % [commander_type, wreck,
		int(unit_catalog.feature(wreck).damage), combat.feature_destructions - destroyed_before, remaining, not economy.units.has(second)])
	return true

func run_reclaim_demo() -> bool:
	# The Commander destroys an adjacent enemy, then reclaims its wreck: metal is credited and the wreck becomes its featurereclamate.
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var point: Vector2 = navigation.nearest_open(unit_position + Vector2(150, 0))
	var enemy: int = economy.add_unit(enemy_type, point, 0.0, 1)
	add_structure_sprite(enemy)
	var deaths_before: int = combat.deaths.size()
	for tick in range(1500):
		step_script()
		if not economy.units.has(enemy):
			break
	if economy.units.has(enemy) or combat.deaths.size() == deaths_before or int(combat.deaths[deaths_before].anchor) < 0:
		printerr("Reclaim demo: no wreck to reclaim")
		return false
	var anchor := int(combat.deaths[deaths_before].anchor)
	var width := int(economy.features.width)
	var wreck: String = economy.features.instances[anchor].name
	var definition: Dictionary = unit_catalog.feature(wreck)
	# Leave storage headroom so the credited metal is visible in stock.
	economy.metal = 0.0
	var reclaimed_before: int = economy.reclaimed.size()
	var started: int = economy.ticks
	@warning_ignore("integer_division")
	if not reclaim_at(Vector2(anchor % width, anchor / width) * 16.0 + Vector2(8, 8)):
		printerr("Reclaim demo: order refused: ", economy.status)
		return false
	for tick in range(1500):
		step_script()
		if economy.reclaimed.size() > reclaimed_before:
			break
	if economy.reclaimed.size() == reclaimed_before:
		printerr("Reclaim demo: not finished: ", economy.reclaim_jobs.get(economy.builder_id, {}))
		return false
	var result: Dictionary = economy.reclaimed[reclaimed_before]
	var stock: float = economy.metal
	for tick in range(40):
		step_script()
	var successor: String = economy.features.instances[anchor].name if economy.features.instances.has(anchor) else ""
	if successor != str(definition.get("featurereclamate", "")) or economy.metal - stock < float(definition.metal) - 1.0 or not script_vm.fault.is_empty():
		printerr("Reclaim demo: successor=%s metal %.1f -> %.1f fault=%s" % [successor, stock, economy.metal, script_vm.fault])
		return false
	print("RECLAIM_VERIFY_OK %s reclaimed %s (%d metal, countdown %d) %d ticks after the order; it became %s; metal %.1f -> %.1f" % [commander_type, wreck,
		int(definition.metal), ConstructionWorld.reclaim_countdown(definition), int(result.tick) - started, successor, stock, economy.metal])
	return true

## Ctrl+D: toggle self-destruct on the selected group, the selected unit, or the Commander.
func toggle_self_destruct() -> void:
	var ids: Array = selected_group.duplicate() if not selected_group.is_empty() else [economy.builder_id if selected_unit == 0 else selected_unit]
	var started: bool = combat.toggle_self_destruct(ids)
	status_label.text = "  Self-destruct %s for %d unit(s)" % ["started" if started else "cancelled", ids.size()]

func run_self_destruct_demo() -> bool:
	# A friendly Flash and Raider self-destruct: countdown voice lines, a reason-3 death and the selfdestructas blast.
	var type := "armflash" if faction == "arm" else "corraid"
	var point: Vector2 = navigation.nearest_open(unit_position + Vector2(0, 260))
	var unit: int = economy.add_unit(type, point, 0.0, 0)
	add_structure_sprite(unit)
	economy.mobile_units[unit] = MobileUnit.new(economy.unit_navigation(type), unit_catalog.definition(type), point, economy.scripts[unit])
	var deaths_before: int = combat.deaths.size()
	selected_group.clear()
	selected_unit = unit
	toggle_self_destruct()
	var started_tick: int = combat.tick
	for tick in range(400):
		step_script()
		if not economy.units.has(unit):
			break
	var voices: Array = combat.voice_requests.filter(func(entry: Array) -> bool: return int(entry[0]) == unit).map(func(entry: Array): return entry[1])
	if economy.units.has(unit) or combat.deaths.size() == deaths_before:
		printerr("Self-destruct demo: unit alive after 400 ticks; voices %s" % [voices])
		return false
	var death: Dictionary = combat.deaths[deaths_before]
	var elapsed: int = int(death.tick) - started_tick
	if voices != ["count5", "count4", "count3", "count2", "count1", "count0"] or elapsed < 151 or elapsed > 165:
		printerr("Self-destruct demo: voices %s, death after %d ticks" % [voices, elapsed])
		return false
	print("SELF_DESTRUCT_VERIFY_OK %s counted down %s and died after %d ticks with severity %d (selfdestructas %s)" % [type, voices, elapsed, int(death.severity),
		unit_catalog.definition(type).get("selfdestructas", "")])
	return true

func choose_dgun() -> void:
	if economy == null or not economy.units.has(economy.builder_id):
		return
	placement_type = DGUN_MODE
	status_label.text = "  D-gun: click an enemy unit (400 energy per shot)"

func dgun_at(point: Vector2) -> bool:
	for id: int in economy.units.keys():
		var unit: Dictionary = economy.units[id]
		if int(unit.get("team", 0)) != 0 and economy.footprint(unit.type, unit.position).grow(8).has_point(point):
			var accepted: bool = combat.command_fire(economy.builder_id, id)
			status_label.text = "  " + combat.status
			return accepted
	# No enemy under the cursor: the mode-3 selector issues a ground (Suppress) command fire at the point.
	var fired: bool = combat.command_fire_ground(economy.builder_id, point)
	status_label.text = "  " + combat.status
	return fired

## G then click: the selected group, unit or Commander fires its primary weapon at the ground point until stopped.
func attack_ground_at(point: Vector2) -> int:
	var ids: Array = selected_group.duplicate() if not selected_group.is_empty() else [economy.builder_id if selected_unit == 0 else selected_unit]
	var accepted := 0
	for id in ids:
		if combat.attack_ground(int(id), point):
			accepted += 1
	status_label.text = "  Attack ground: %d unit(s) suppressing" % accepted
	return accepted

func run_ground_attack_demo() -> bool:
	# A friendly cannon tank shells a ground point repeatedly; then the Commander D-guns a ground point beyond an enemy.
	var type := "armstump" if faction == "arm" else "corraid"
	var point: Vector2 = navigation.nearest_open(unit_position + Vector2(-200, 0))
	var tank: int = economy.add_unit(type, point, 0.0, 0)
	add_structure_sprite(tank)
	economy.mobile_units[tank] = MobileUnit.new(economy.unit_navigation(type), unit_catalog.definition(type), point, economy.scripts[tank])
	selected_group.clear()
	selected_unit = tank
	var target: Vector2 = point + Vector2(0, 150)
	if attack_ground_at(target) != 1:
		return false
	var shots: int = combat.shots_fired
	for tick in range(360):
		step_script()
	var fired: int = combat.shots_fired - shots
	if fired < 2 or not combat.orders.has(tank) or not combat.orders[tank].has("point"):
		printerr("Ground attack demo: %s fired %d shots, order present %s" % [type, fired, combat.orders.has(tank)])
		return false
	combat.stop(tank)
	selected_unit = 0
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var enemy: int = economy.add_unit(enemy_type, navigation.nearest_open(unit_position + Vector2(0, 200)), 0.0, 1)
	add_structure_sprite(enemy)
	combat.guards.erase(economy.builder_id)
	var dgun_shots: int = combat.shots_fired
	# The ground point sits under the enemy, so the D-gun descends into it.
	if not combat.command_fire_ground(economy.builder_id, economy.units[enemy].position):
		printerr("Ground attack demo: ground D-gun refused: ", combat.status)
		return false
	for tick in range(300):
		step_script()
		if combat.shots_fired > dgun_shots and not combat.command_orders.has(economy.builder_id) and combat.projectiles.is_empty():
			break
	if combat.shots_fired != dgun_shots + 1 or combat.command_orders.has(economy.builder_id) or economy.units.has(enemy):
		printerr("Ground attack demo: D-gun shots %d, order left %s, enemy alive %s" % [combat.shots_fired - dgun_shots, combat.command_orders.has(economy.builder_id), economy.units.has(enemy)])
		return false
	print("GROUND_ATTACK_VERIFY_OK %s fired %d shots at the ground over 360 ticks and kept suppressing; %s ground D-gun at the ground under %s fired once, completed and destroyed it" % [type, fired, commander_type, enemy_type])
	return true

func run_dgun_demo() -> bool:
	# Three enemies in a row; one D-gun shot aimed at the nearest must destroy all of them.
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var enemies: Array = []
	for distance in [110, 150, 190]:
		var point: Vector2 = navigation.nearest_open(unit_position + Vector2(0, distance))
		if point.x < 0:
			return false
		var id: int = economy.add_unit(enemy_type, point, 0.0, 1)
		add_structure_sprite(id)
		enemies.append(id)
	combat.guards.erase(economy.builder_id)
	var energy_before: float = economy.energy
	if not dgun_at(economy.units[enemies[0]].position):
		return false
	var shots: int = combat.shots_fired
	for tick in range(600):
		step_script()
		if combat.shots_fired > shots and combat.projectiles.is_empty():
			break
	var survivors := 0
	for id: int in enemies:
		survivors += int(economy.units.has(id))
	if survivors != 0 or combat.shots_fired != shots + 1 or not script_vm.fault.is_empty():
		printerr("D-gun demo: survivors=%d shots=%d fault=%s energy %.1f -> %.1f" % [survivors, combat.shots_fired - shots, script_vm.fault, energy_before, economy.energy])
		return false
	print("DGUN_VERIFY_OK %s D-gun destroyed %d %s in one shot; energy %.0f -> %.0f" % [commander_type, enemies.size(), enemy_type, energy_before, economy.energy])
	return true

func run_commander_combat() -> bool:
	# An enemy of the other faction appears inside laser range; the holding guard must destroy it in place.
	var enemy_type := "armflash" if faction == "core" else "corraid"
	var start: Vector2 = mobile.point()
	var point: Vector2 = navigation.nearest_open(unit_position + Vector2(160, 0))
	if point.x < 0:
		return false
	var enemy: int = economy.add_unit(enemy_type, point, 0.0, 1)
	add_structure_sprite(enemy)
	var shots: int = combat.shots_fired
	for tick in range(1500):
		step_script()
		if not economy.units.has(enemy):
			break
	if economy.units.has(enemy) or combat.shots_fired == shots or not script_vm.fault.is_empty() or mobile.point() != start:
		printerr("Commander combat: enemy alive=%s shots=%d fault=%s moved=%s" % [economy.units.has(enemy), combat.shots_fired - shots, script_vm.fault, mobile.point() != start])
		return false
	print("COMMANDER_VERIFY_OK %s destroyed an adjacent %s with its laser while holding position" % [commander_type, enemy_type])
	return true

func run_core_factory_demo() -> bool:
	if faction != "core":
		return false
	# Unverified Core entries remain listed but must not be placeable.
	select_unit(0)
	for index in range(build_picker.item_count):
		var type: String = build_picker.get_item_metadata(index)
		if build_picker.is_item_disabled(index) == ConstructionWorld.supported(type):
			return false
	if place_structure("corllt", unit_position + Vector2(0, 96)):
		return false
	for order: Array in [["corvp", "corraid", -1.0], ["corlab", "corak", 1.0]]:
		# Starting stock cannot fund both factories and products; refill so the demo exercises scripts, not income.
		economy.energy = economy.energy_storage
		economy.metal = economy.metal_storage
		if not run_factory_demo(order[0], order[1], 1, order[2]):
			printerr("Core factory demo stopped at ", order[0], ": ", economy.status)
			return false
	print("CORE_FACTORY_VERIFY_OK Core Commander built corvp and corlab (stock refilled before each); each produced one unit; unverified menu entries gated")
	return true

func run_builder_demo() -> bool:
	var prefix := "cor" if faction == "core" else "arm"
	if not run_factory_demo(prefix + "vp", prefix + "cv", 1):
		return false
	var source := 0
	for unit: Dictionary in economy.units.values():
		if unit.type == prefix + "cv":
			source = unit.id
	if source == 0:
		return false
	select_unit(source)
	for index in range(build_picker.item_count):
		if build_picker.get_item_metadata(index) == prefix + "solar":
			build_picker.select(index)
	choose_build()
	var point: Vector2 = economy.units[source].position + Vector2(-64, 0)
	# Footprints differ by faction; try nearby sites in a fixed order and take the first the world accepts.
	for offset: Vector2 in [Vector2(-64, 0), Vector2(64, 0), Vector2(0, 64), Vector2(-64, 64), Vector2(64, 64)]:
		var candidate: Vector2 = economy.units[source].position + offset
		if economy.placement_error(prefix + "solar", candidate.snapped(Vector2(16, 16)), source).is_empty():
			point = candidate
			break
	if placement_type != prefix + "solar" or not place_structure(placement_type, point):
		printerr("Builder demo placement failed: type=", placement_type, " ", status_label.text)
		return false
	var target: int = economy.builder_jobs[source].target
	for tick in range(1800):
		step_script()
	if float(economy.units[target].remaining) != 0 or economy.builder_jobs.has(source) or not economy.scripts[source].fault.is_empty():
		printerr("Builder demo stopped: ", economy.status, " remaining=", economy.units[target].remaining)
		return false
	print("BUILDER_VERIFY_OK faction=%s factory-produced Construction Vehicle built a solar collector through selected-unit controls" % faction)
	return true

func issue_move(target: Vector2) -> bool:
	if selected_unit != 0:
		var accepted: bool = economy.move_unit(selected_unit, target)
		if accepted:
			combat.stop(selected_unit, false)
		status_label.text = "  Move order accepted" if accepted else "  Select a completed mobile unit to move"
		return accepted
	if mobile == null:
		return false
	if economy != null:
		economy.stop_build()
	if building:
		toggle_build()
	if not mobile.move_to(target):
		status_label.text = "  " + mobile.status
		return false
	if combat != null and economy != null:
		combat.stop(economy.builder_id, false)
	if walking:
		walking = false
		script_vm.invoke("StopMoving")
		walk_button.text = "Play walk cycle  [Space]"
	route_line.points = mobile.route
	status_label.text = "  Move order accepted — %d route points" % mobile.route.size()
	return true

func stop_order() -> void:
	placement_type = ""
	if not selected_group.is_empty() and economy != null:
		for id: int in selected_group:
			if economy.units.has(id):
				combat.stop(id)
				if economy.mobile_units.has(id):
					economy.mobile_units[id].stop()
		status_label.text = "  Group stop"
		return
	if combat != null:
		combat.stop(selected_unit if selected_unit != 0 or economy == null else economy.builder_id)
	if selected_unit != 0 and economy.mobile_units.has(selected_unit):
		economy.stop_build(selected_unit)
		economy.mobile_units[selected_unit].stop()
		return
	if selected_unit != 0:
		return
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
	if build_picker.selected < 0 or build_picker.disabled:
		return
	stop_order()
	placement_type = str(build_picker.get_item_metadata(build_picker.selected))
	var fields: Dictionary = unit_catalog.definition(placement_type)
	status_label.text = "  Place %s nearby · %s metal / %s energy · Right-click cancels" % [fields.name, fields.get("buildcostmetal", "0"), fields.get("buildcostenergy", "0")]

func place_structure(type: String, point: Vector2) -> bool:
	var source_id: int = economy.builder_id if selected_unit == 0 else selected_unit
	var controller: RefCounted = mobile if selected_unit == 0 else economy.mobile_units.get(selected_unit)
	if controller == null or controller.speed != 0:
		status_label.text = "  Wait for a construction unit to stop before placing"
		return false
	var id: int = economy.begin_build(type, point, source_id)
	if id == 0:
		status_label.text = "  " + economy.status
		return false
	placement_type = ""
	add_structure_sprite(id)
	economy.refresh_navigation(true)
	if selected_unit == 0 and not building:
		toggle_build()
	return true

func sync_feature_sprites() -> void:
	if economy == null or economy.features.revision == feature_sprite_revision:
		return
	feature_sprite_revision = economy.features.revision
	var added_flat := false
	for anchor: int in feature_sprites.keys():
		# Replacements (wreck -> heap) reuse the anchor; rebuild the sprite when the feature name changes.
		if not economy.features.instances.has(anchor) or str(feature_sprites[anchor].get_meta("feature", "")) != str(economy.features.instances[anchor].name):
			feature_sprites[anchor].queue_free()
			feature_sprites.erase(anchor)
	for anchor: int in economy.features.instances:
		if feature_sprites.has(anchor):
			continue
		var instance: Dictionary = economy.features.instances[anchor]
		if unit_catalog.load_feature_model(instance.name).is_empty():
			var flat := feature_sprite_2d(anchor, str(instance.name))
			if flat != null:
				feature_sprites[anchor] = flat
				added_flat = true
			continue
		var key: String = "feature:" + str(instance.name)
		var sprite := Sprite2D.new()
		sprite.texture = structure_texture(key, -anchor - 1)
		sprite.set_meta("feature", str(instance.name))
		sprite.position = Vector2(float(instance.position_raw[0]), float(instance.position_raw[2])) / 65536.0
		sprite.scale = Vector2.ONE * (0.28 * 192.0 / 55.0)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		world.add_child(sprite)
		feature_sprites[anchor] = sprite
	if added_flat:
		order_feature_layers()

## A 2D GAF feature drawn as 0x46a610 does: shadow frame then main frame, each blitted with its top-left at the
## anchor minus the frame's x/y offsets. The map draw loop never visits the last column or row, so features anchored
## there are not drawn. Features at least 10 high draw above ground units; lower ones beneath them.
func feature_sprite_2d(anchor: int, name: String) -> Node2D:
	var sprites: Dictionary = unit_catalog.feature_sprites(name)
	if not sprites.has("sprite"):
		return null
	var width: int = economy.features.width
	var rows: int = economy.features.height
	@warning_ignore("integer_division")
	var cell := Vector2i(anchor % width, anchor / width)
	if cell.x >= width - 1 or cell.y >= rows - 1:
		return null
	var definition: Dictionary = unit_catalog.feature(name)
	var point := FeatureAnimation.anchor(navigation.heights, width, rows, cell.x, cell.y, int(definition.get("footprintx", 1)), int(definition.get("footprintz", 1)))
	var node := Node2D.new()
	node.position = Vector2(point)
	node.set_meta("feature", name)
	node.set_meta("anchor", anchor)
	for key: String in ["shadow", "sprite"]:
		if not sprites.has(key) or sprites[key].frames.is_empty():
			continue
		var frames: Array = sprites[key].frames
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# animtrans/shadtrans select the translucent blitter; rendered here as half alpha.
		if bool(definition.get("shadtrans" if key == "shadow" else "animtrans", false)):
			sprite.modulate.a = 0.5
		sprite.name = key
		node.add_child(sprite)
		if bool(definition.get("animating", false)):
			# Separate shared states for the main (+0xcc) and shadow (+0xd8) sequences of the type.
			var shared := feature_animation(name, key)
			shared.sprites.append(sprite)
			apply_feature_frame(sprite, frames, shared.state)
		else:
			apply_feature_frame(sprite, frames, {"active": true, "index": 0})
	# Pass A (height below 10) draws before units; pass B after the ground units of the row. Approximated with two layers.
	feature_layer(int(definition.get("height", 0)) >= 10).add_child(node)
	return node

## Low and tall 2D feature layers: low sits just above the terrain, tall above ground units.
func feature_layer(tall: bool) -> Node2D:
	if feature_layers.is_empty():
		for index in range(2):
			var layer := Node2D.new()
			layer.name = "tall_features" if index == 1 else "low_features"
			layer.z_index = index
			world.add_child(layer)
			world.move_child(layer, 1 + index)
			feature_layers.append(layer)
	return feature_layers[1 if tall else 0]

## Keep each layer in row-major anchor order (later nodes overdraw earlier ones, as the original's row walk does).
func order_feature_layers() -> void:
	for layer: Node2D in feature_layers:
		var children: Array = layer.get_children()
		var sorted := children.duplicate()
		sorted.sort_custom(func(a, b) -> bool: return int(a.get_meta("anchor", 0)) < int(b.get_meta("anchor", 0)))
		if sorted == children:
			continue
		for index in range(sorted.size()):
			layer.move_child(sorted[index], index)

## Shared animation state of one type and sequence, created at frame 0 on first use (or at map load, see prime_feature_animations).
func feature_animation(name: String, key: String) -> Dictionary:
	var id := name + ":" + key
	if not feature_animations.has(id):
		var sequence: Dictionary = unit_catalog.feature_sprites(name).get(key, {})
		var durations: Array = sequence.get("durations", [])
		feature_animations[id] = {"state": FeatureAnimation.start(durations), "durations": durations, "loop": int(sequence.get("loop", 0)) != 0,
			"frames": sequence.get("frames", []), "sprites": []}
	return feature_animations[id]

## 0x4224b0 arms the shared states when a definition loads, so every animating type on the map starts before tick 1.
func prime_feature_animations() -> void:
	for anchor: int in economy.features.instances:
		var name: String = economy.features.instances[anchor].name
		if bool(unit_catalog.feature(name).get("animating", false)):
			for key: String in unit_catalog.feature_sprites(name):
				feature_animation(name, key)

## A sequence whose state ended (seq cleared in 0x4b8b90) yields no frame, so nothing is drawn.
func apply_feature_frame(sprite: Sprite2D, frames: Array, state: Dictionary) -> void:
	var index := int(state.get("index", 0))
	if not bool(state.get("active", false)) or index < 0 or index >= frames.size():
		sprite.visible = false
		return
	var frame: Dictionary = frames[index]
	sprite.visible = true
	sprite.texture = unit_catalog.feature_texture(str(frame.image))
	sprite.offset = Vector2(-float(frame.x), -float(frame.y))

## 0x424050: every animating feature type advances its shared states once per simulation tick, so instances move in lockstep.
func step_feature_animations() -> void:
	for id: String in feature_animations.keys():
		var shared: Dictionary = feature_animations[id]
		if FeatureAnimation.step(shared.state, shared.durations, shared.loop):
			var live: Array = shared.sprites.filter(func(sprite) -> bool: return is_instance_valid(sprite))
			shared.sprites = live
			for sprite: Sprite2D in live:
				apply_feature_frame(sprite, shared.frames, shared.state)

func add_structure_sprite(id: int) -> void:
	var unit: Dictionary = economy.units[id]
	var type: String = unit.type
	var sprite := Sprite2D.new()
	sprite.texture = structure_texture(type, id)
	sprite.position = unit.position
	sprite.scale = Vector2.ONE * (0.28 * 192.0 / 55.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(sprite)
	structure_sprites[id] = sprite

func structure_texture(type: String, id: int) -> Texture2D:
	var individual: bool = economy.units.has(id) and (economy.scripts.has(id) or economy.units[id].has("produced_by"))
	var key := str(id) if individual else type
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
	if individual:
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

func select_unit(id: int) -> void:
	if id != 0 and economy.units.has(id) and int(economy.units[id].get("team", 0)) != 0:
		status_label.text = "  Select one of your units"
		return
	selected_unit = id
	placement_type = ""
	var source_id: int = economy.builder_id if id == 0 else id
	if not economy.units.has(source_id):
		selection_label.text = "Commander destroyed"
		build_picker.disabled = true
		place_button.disabled = true
		factory_controls.visible = false
		return
	selection_label.text = "Selected: " + unit_catalog.definition(economy.units[source_id].type).get("name", economy.units[source_id].type)
	var builder: bool = economy.can_build(source_id)
	build_picker.clear()
	build_picker.disabled = not builder
	place_button.disabled = not builder
	if builder:
		fill_build_picker(build_picker, economy.units[source_id].type)
	factory_controls.visible = economy != null and economy.factories.has(id)
	if factory_controls.visible:
		factory_picker.clear()
		fill_build_picker(factory_picker, economy.units[id].type)
	update_world()

func fill_build_picker(picker: OptionButton, source_type: String) -> void:
	var first_enabled := -1
	for type: String in unit_catalog.build_options(source_type):
		var verified: bool = ConstructionWorld.supported(type)
		picker.add_item(unit_catalog.definition(type).get("name", type) + ("" if verified else " (unverified)"))
		picker.set_item_metadata(picker.item_count - 1, type)
		picker.set_item_disabled(picker.item_count - 1, not verified)
		if verified and first_enabled < 0:
			first_enabled = picker.item_count - 1
	picker.select(first_enabled)

func queue_factory_unit() -> void:
	if economy.factories.has(selected_unit) and factory_picker.selected >= 0:
		economy.queue_unit(selected_unit, str(factory_picker.get_item_metadata(factory_picker.selected)))
		status_label.text = "  " + economy.factories[selected_unit].status

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
	model_root = unit_visuals.instantiate(commander_type)
	model_view.add_child(model_root)
	piece_nodes.assign(model_root.get_meta("pieces"))
	rig_nodes = model_root.get_meta("rig")
	rig_origins = model_root.get_meta("origins")
	var max_y := 0.0
	var min_y := 0.0
	var model_pieces: Array = unit_catalog.load_unit(commander_type).model.pieces
	for index in range(mini(model_pieces.size(), piece_nodes.size())):
		for vertex: Array in model_pieces[index].vertices:
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
	var data: Dictionary = unit_catalog.load_script(commander_type)
	if data.is_empty():
		status_label.text = "  Missing COB data for " + commander_type + ". Run python tools/prepare_units.py."
		printerr("FAIL: missing commander script for ", commander_type)
		if "--verify" in OS.get_cmdline_user_args() or "--faction" in OS.get_cmdline_user_args():
			get_tree().quit(1)
		return
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
	if scenario_result != null and scenario_result.outcome != "active":
		return
	if script_vm == null or not script_vm.fault.is_empty():
		return
	if economy != null and not economy.units.has(economy.builder_id):
		status_label.text = "  Commander destroyed — restart the development build to play again"
		unit_sprite.hide()
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
		var selected_target: int = economy.builder_jobs[selected_unit].target if economy.builder_jobs.has(selected_unit) else 0
		economy.step()
		step_feature_animations()
		if economy.ticks % 10 == 0:
			refresh_minimap()
		if opponent != null:
			opponent.step()
		combat.step()
		check_scenario_result()
		combat_overlay.queue_redraw()
		sync_feature_sprites()
		for id: int in structure_sprites.keys():
			if not economy.units.has(id):
				structure_sprites[id].queue_free()
				structure_sprites.erase(id)
				structure_models.erase(id)
				if structure_views.has(str(id)):
					structure_views[str(id)].queue_free()
					structure_views.erase(str(id))
				if selected_unit == id:
					select_unit(0)
		for id: int in economy.units:
			if id != economy.builder_id and not structure_sprites.has(id):
				add_structure_sprite(id)
		resource_label.text = preload("res://resource_display.gd").describe(economy.resources(0))
		for id: int in structure_sprites:
			structure_sprites[id].position = economy.units[id].position
			var remaining := float(economy.units[id].remaining)
			structure_sprites[id].modulate = Color(1, 1, 1, 0.25 + 0.75 * (1.0 - remaining))
			if structure_models.has(id) and economy.scripts.has(id):
				UnitVisuals.apply_pose(structure_models[id], economy.scripts[id].pieces)
			if economy.mobile_units.has(id):
				structure_models[id].rotation.y = -float(economy.mobile_units[id].heading) * TAU / 65536.0
		if economy.factories.has(selected_unit):
			var factory: Dictionary = economy.factories[selected_unit]
			factory_label.text = "%s · %d queued\n%s" % [unit_catalog.definition(economy.units[selected_unit].type).name, factory.queue.size(), factory.status]
		update_world()
		if was_building:
			status_label.text = "  " + economy.status
		if was_building and economy.task_id == 0 and building:
			toggle_build()
			status_label.text = "  Construction complete"
		var reclaimer: int = economy.builder_id if selected_unit == 0 else selected_unit
		if economy.reclaim_jobs.has(reclaimer):
			status_label.text = "  " + economy.reclaim_jobs[reclaimer].status
		elif economy.builder_jobs.has(selected_unit):
			status_label.text = "  " + economy.builder_jobs[selected_unit].status
		elif selected_target != 0 and selected_target in economy.completed:
			status_label.text = "  Construction complete"
		if not combat.destroyed.is_empty():
			status_label.text = "  Unit destroyed"
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
	terrain_sprite.scale = Vector2.ONE * float(scene_data.get("terrain_scale", 1))
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
	column.add_child(label(str(scene_data.name).to_upper(), 21, Color("edf0e8")))
	column.add_child(label("%d × %d  ·  Original terrain tiles" % [int(scene_data.width), int(scene_data.height)], 12))
	column.add_child(build_map_picker())
	minimap = Minimap.new()
	var minimap_image = image_texture("minimap.png", map_assets)
	minimap.setup(minimap_image if minimap_image != null else terrain, Vector2(float(scene_data.width), float(scene_data.height)))
	minimap.view_requested.connect(func(point: Vector2) -> void:
		map_center = point
		update_world())
	column.add_child(minimap)
	var preview := TextureRect.new()
	preview.texture = model_view.get_texture()
	preview.custom_minimum_size = Vector2(230, 150)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(preview)
	var commander_name: String = unit_catalog.definition(commander_type).get("name", commander_type)
	column.add_child(label(("CORE COMMANDER" if faction == "core" else "ARM COMMANDER"), 20, Color("d5e4ac")))
	column.add_child(label("Original geometry, textures & script", 13))
	var faction_row := HBoxContainer.new()
	column.add_child(faction_row)
	var arm_button := button("Arm", func() -> void: switch_faction("arm"))
	arm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arm_button.disabled = faction == "arm"
	faction_row.add_child(arm_button)
	var core_button := button("Core", func() -> void: switch_faction("core"))
	core_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	core_button.disabled = faction == "core"
	faction_row.add_child(core_button)
	resource_label = label("Metal 1000\nEnergy 1000", 14, Color("d5e4ac"))
	resource_label.tooltip_text = "Income and demand show the last resource update. Unpaid costs can pause construction or metal production until repaid."
	column.add_child(resource_label)
	selection_label = label("Selected: " + commander_name, 13)
	column.add_child(selection_label)
	build_picker = OptionButton.new()
	fill_build_picker(build_picker, commander_type)
	column.add_child(build_picker)
	place_button = button("Place selected structure", choose_build)
	column.add_child(place_button)
	factory_controls = VBoxContainer.new()
	factory_controls.visible = false
	column.add_child(factory_controls)
	factory_label = label("Factory", 12)
	factory_controls.add_child(factory_label)
	factory_picker = OptionButton.new()
	factory_controls.add_child(factory_picker)
	factory_controls.add_child(button("Queue unit", queue_factory_unit))
	factory_controls.add_child(button("Clear pending orders", func() -> void: economy.clear_factory_queue(selected_unit)))
	column.add_child(button("Select Commander", func() -> void:
		selected_group.clear()
		combat_overlay.selected = []
		select_unit(0)))
	column.add_child(label("Shift+drag selects units · A selects army", 11))
	column.add_child(button("Add practice target", func() -> void: add_practice_target()))
	column.add_child(button("Add armed Raider", add_armed_raider))
	column.add_child(button("Start opponent", start_opponent))
	column.add_child(label("Click terrain to move · Right-click / S to stop", 11))
	column.add_child(button("Stop movement  [S]", stop_order))
	column.add_child(button("D-gun target  [D]", choose_dgun))
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
	selection.position = (economy.units[selected_unit].position if selected_unit != 0 and economy != null else unit_position) + Vector2(0, 15)
	unit_sprite.position = unit_position
	if zoom_label != null:
		zoom_label.text = "Zoom  %d%%" % roundi(map_zoom * 100)
	refresh_minimap()

func refresh_minimap() -> void:
	if minimap == null or economy == null:
		return
	var extent: Vector2 = map_panel.size / map_zoom
	minimap.refresh(economy.units, Rect2(map_center - extent * 0.5, extent))

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
			var world_point: Vector2 = (event.position - world.position) / map_zoom
			if event.pressed and event.shift_pressed and economy != null:
				box_start = world_point
				dragging = false
				return
			if not event.pressed and box_start != Vector2.INF:
				var rect := Rect2(box_start, world_point - box_start)
				box_start = Vector2.INF
				combat_overlay.box = Rect2()
				if rect.abs().size.length() >= 5:
					status_label.text = "  Selected %d units" % select_group_in_rect(rect)
				update_world()
				return
			dragging = event.pressed
			if event.pressed:
				set_meta("press_position", event.position)
			elif event.position.distance_to(get_meta("press_position", event.position)) < 5:
				var pos: Vector2 = (event.position - world.position) / map_zoom
				var group_handled := false
				if placement_type.is_empty() and not selected_group.is_empty():
					group_handled = true
					var clicked := 0
					for id: int in economy.units:
						if economy.footprint(economy.units[id].type, economy.units[id].position).has_point(pos):
							clicked = id
					if clicked != 0 and int(economy.units[clicked].get("team", 0)) != 0:
						group_attack(clicked)
					elif clicked != 0:
						group_handled = false
						selected_group.clear()
						combat_overlay.selected = []
					else:
						group_move(pos)
				if group_handled:
					pass
				elif placement_type == GROUND_ATTACK_MODE:
					placement_type = ""
					attack_ground_at(pos)
				elif placement_type == DGUN_MODE:
					placement_type = ""
					dgun_at(pos)
				elif not placement_type.is_empty():
					place_structure(placement_type, pos)
				else:
					var resumed := false
					var ids: Array = structure_sprites.keys()
					ids.reverse()
					for id: int in ids:
						var unit: Dictionary = economy.units[id]
						if int(unit.get("team", 0)) != 0 and economy.footprint(unit.type, unit.position).has_point(pos):
							combat.attack(economy.builder_id if selected_unit == 0 else selected_unit, id, true)
							status_label.text = "  " + combat.status
							resumed = true
							break
						if economy.footprint(unit.type, unit.position).has_point(pos) and (economy.factories.has(id) or economy.mobile_units.has(id)) and float(unit.remaining) == 0:
							select_unit(id)
							resumed = true
							break
						if economy.footprint(unit.type, unit.position).has_point(pos) and economy.set_active(id, not bool(unit.active)):
							status_label.text = "  Solar collector " + ("on" if unit.active else "off")
							resumed = true
							break
						var source_id: int = economy.builder_id if selected_unit == 0 else selected_unit
						if economy.footprint(unit.type, unit.position).has_point(pos) and economy.resume_build(id, source_id):
							if selected_unit == 0:
								mobile.stop()
							if selected_unit == 0 and not building:
								toggle_build()
							resumed = true
							break
					if not resumed:
						resumed = reclaim_at(pos)
					if not resumed:
						issue_move(pos)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			stop_order()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector2 = (event.position - world.position) / map_zoom
			var factor := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			map_zoom = clampf(map_zoom * factor, 0.04, 8.0)
			map_center = before - (event.position - map_panel.size * 0.5) / map_zoom
	elif event is InputEventMouseMotion and box_start != Vector2.INF:
		combat_overlay.box = Rect2(box_start, (event.position - world.position) / map_zoom - box_start)
		combat_overlay.queue_redraw()
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
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9 and economy != null and (event.ctrl_pressed or event.alt_pressed):
		# Default (SwitchAlt off): Ctrl+digit creates a squad, Alt+digit selects it (Shift adds).
		var squad: int = event.keycode - KEY_0
		if event.ctrl_pressed:
			create_squad(squad)
		else:
			select_squad(squad, event.shift_pressed)
	elif event.keycode == KEY_A and event.ctrl_pressed and economy != null:
		status_label.text = "  Selected all: %d units" % select_all_own()
	elif event.keycode == KEY_Z and event.ctrl_pressed and economy != null:
		status_label.text = "  Selected matching types: %d units" % select_same_types()
	elif event.keycode == KEY_ESCAPE:
		if not placement_type.is_empty():
			placement_type = ""
			status_label.text = "  Order cancelled"
		elif economy != null:
			select_group([])
	elif event.keycode == KEY_1:
		aim_and_fire()
	elif event.keycode == KEY_2:
		aim_and_fire(true)
	elif event.keycode == KEY_C:
		clear_target()
	elif event.keycode == KEY_B:
		toggle_build()
	elif event.keycode == KEY_G and economy != null:
		placement_type = GROUND_ATTACK_MODE
		status_label.text = "  Attack ground: click a map point"
	elif event.keycode == KEY_D and event.ctrl_pressed and economy != null:
		toggle_self_destruct()
	elif event.keycode == KEY_D:
		choose_dgun()
	elif event.keycode == KEY_A and economy != null:
		status_label.text = "  Selected army: %d units" % select_army()

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
		if world == null or piece_nodes.size() != 15 or (map_slug.is_empty() and terrain.get_width() != 6144):
			get_tree().quit(1)
			return
		# Commander and produced-unit navigation must both consume the prepared feature-blocking grid.
		var cells: int = navigation.width * navigation.height
		if navigation.features.size() != cells or economy.unit_navigation("armflash").features != navigation.features:
			printerr("FAIL: live navigation is missing the prepared feature-blocking grid")
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
		assert(run_factory_demo(), "Factory build, queue, exit or movement failed")
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

func start_opponent() -> void:
	if opponent != null:
		status_label.text = "  Opponent already active"
		return
	# The opponent plays the other faction, as in an Arm versus Core skirmish.
	var opponent_faction := "arm" if faction == "core" else "core"
	# A skirmish computer player starts with its own Commander (not a construction vehicle) and the schema's
	# ComputerMetal/ComputerEnergy; the human player keeps HumanMetal/HumanEnergy.
	var builder_type: String = Opponent.FACTIONS[opponent_faction].commander
	var nav = economy.unit_navigation(builder_type)
	# On prepared skirmish maps the opponent takes the second OTA start position; the demo map keeps nearby offsets.
	var candidates: Array = []
	var starts: Array = scene_data.get("start_positions", [])
	if starts.size() > 1:
		var second := Vector2(float(starts[1].x), float(starts[1].z))
		candidates.append_array([second, second + Vector2(96, 0), second + Vector2(0, 96), second + Vector2(-96, 0), second + Vector2(0, -96)])
	for offset in [Vector2(512, 0), Vector2(-512, 0), Vector2(0, 512), Vector2(0, -512)]:
		candidates.append(unit_position + offset)
	for candidate: Vector2 in candidates:
		var point: Vector2 = nav.nearest_open(candidate)
		if point.x < 0 or point.distance_to(unit_position) < 256:
			continue
		var occupied := false
		for unit: Dictionary in economy.units.values():
			occupied = occupied or economy.footprint(builder_type, point).intersects(economy.footprint(unit.type, unit.position))
		if occupied:
			continue
		var id: int = economy.add_unit(builder_type, point, 0, 1, true)
		economy.mobile_units[id] = MobileUnit.new(nav, unit_catalog.definition(builder_type), point, economy.scripts[id])
		economy.mobile_units[id].heading = 32768
		apply_schema_resources()
		combat.enable_guard(id, false)
		var policy := Opponent.new(economy, combat, 1, opponent_faction)
		policy.build_base()
		if policy.structures_started == 0:
			economy.remove_unit(id)
			continue
		opponent = policy
		scenario_result = ScenarioResult.new()
		add_structure_sprite(id)
		status_label.text = "  Opponent active  -  build an army to defend your Commander"
		return
	status_label.text = "  No nearby opponent build site found"

## OTA schema starting resources: HumanMetal/HumanEnergy for the player (team 0), ComputerMetal/ComputerEnergy for the AI.
func apply_schema_resources() -> void:
	var schema: Dictionary = scene_data.get("schema", {})
	if schema.is_empty():
		return
	var human: Dictionary = economy.resources(0)
	human.metal = minf(float(str(schema.get("humanmetal", "1000")).to_int()), float(human.metal_storage))
	human.energy = minf(float(str(schema.get("humanenergy", "1000")).to_int()), float(human.energy_storage))
	economy.store_resources(0, human)
	var computer: Dictionary = economy.resources(1)
	computer.metal = minf(float(str(schema.get("computermetal", "1000")).to_int()), float(computer.metal_storage))
	computer.energy = minf(float(str(schema.get("computerenergy", "1000")).to_int()), float(computer.energy_storage))
	economy.store_resources(1, computer)

func run_skirmish_start() -> bool:
	# Real-map skirmish: the computer's Commander appears at OTA start position 2 with ComputerMetal/ComputerEnergy
	# and starts building its base with the normal construction and production rules.
	var starts: Array = scene_data.get("start_positions", [])
	if starts.size() < 2:
		printerr("Skirmish start: map has no second start position")
		return false
	start_opponent()
	if opponent == null:
		printerr("Skirmish start: opponent not created: ", status_label.text)
		return false
	var enemy := 0
	for id: int in economy.units:
		if int(economy.units[id].get("team", 0)) == 1 and economy.units[id].type == Opponent.FACTIONS[opponent.faction].commander:
			enemy = id
	var second := Vector2(float(starts[1].x), float(starts[1].z))
	var account: Dictionary = economy.resources(1)
	if enemy == 0 or economy.units[enemy].position.distance_to(second) > 128 or not economy.scripts.has(enemy):
		printerr("Skirmish start: enemy Commander %d at %s, start 2 at %s" % [enemy, economy.units[enemy].position if enemy != 0 else Vector2.ZERO, second])
		return false
	for tick in range(1800):
		step_script()
	if opponent.structures_started < 2 or not economy.scripts[enemy].fault.is_empty():
		printerr("Skirmish start: structures %d, fault %s" % [opponent.structures_started, economy.scripts[enemy].fault])
		return false
	print("SKIRMISH_START_OK %s: %s Commander at start 2 %s with %d metal / %d energy; started %d structures in 1800 ticks" % [scene_data.name,
		economy.units[enemy].type, second, int(account.metal), int(account.energy), opponent.structures_started])
	return true

func check_scenario_result() -> void:
	if scenario_result == null or scenario_result.outcome != "active":
		return
	var result: String = scenario_result.update(economy.units, economy.builder_id)
	if result == "active":
		return
	var message := "Victory - enemy forces eliminated" if result == "victory" else "Defeat - Commander destroyed"
	status_label.text = "  " + message
	if DisplayServer.get_name() == "headless":
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Battle finished"
	dialog.dialog_text = message
	dialog.ok_button_text = "Restart"
	dialog.dialog_close_on_escape = false
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: get_tree().reload_current_scene())
	dialog.canceled.connect(func() -> void: get_tree().reload_current_scene())
	dialog.popup_centered()
