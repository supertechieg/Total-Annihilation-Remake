extends SceneTree
## Every prepared skirmish map loads into the host world: features, voids and blocking agree with the bundle, metal
## loads, both first start positions reach open ground, and the world steps.
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const FeatureWorld = preload("res://feature_world.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://../local/maps/")
	var index = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("index.json")))
	if not index is Dictionary:
		printerr("Run tools/prepare_maps.py first")
		quit(1)
		return
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var movement: Dictionary = catalog.movement("armcom")
	var loaded := 0
	var started := Time.get_ticks_msec()
	for entry: Dictionary in index.maps:
		if not bool(entry.get("supported", false)):
			continue
		var folder := root.path_join(entry.slug)
		var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("scene.json")))
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("metal.json")))
		var width := int(scene.height_grid_width)
		var height := int(scene.height_grid_height)
		var blocking := FileAccess.get_file_as_bytes(folder.path_join("features.bin"))
		var heights := FileAccess.get_file_as_bytes(folder.path_join("heights.bin"))
		check(blocking.size() == width * height and heights.size() == width * height, entry.slug + " grids match the map size")
		var navigation = Navigation.new(width, height, heights, int(scene.sea_level), int(movement.get("maxslope", 255)), int(movement.get("maxwaterdepth", 10000)),
			Vector2i(int(movement.get("footprintx", 2)), int(movement.get("footprintz", 2))), int(movement.get("minwaterdepth", -10000)), int(movement.get("maxwaterslope", 255)), blocking)
		var starts: Array = scene.start_positions
		var first: Vector2 = navigation.nearest_open(Vector2(float(starts[0].x), float(starts[0].z)))
		var second: Vector2 = navigation.nearest_open(Vector2(float(starts[1].x), float(starts[1].z)))
		check(first.x >= 0 and second.x >= 0 and first.distance_to(Vector2(float(starts[0].x), float(starts[0].z))) < 160, entry.slug + " start positions reach open ground")
		var world = World.new(catalog, navigation, first)
		check(world.set_terrain_metal(FileAccess.get_file_as_bytes(folder.path_join("metal.bin"))), entry.slug + " metal map loads")
		var placed: int = world.load_map_features(metadata.placements, metadata.get("voids", []))
		check(placed == metadata.placements.size(), "%s places all %d loaded features (%d)" % [entry.slug, metadata.placements.size(), placed])
		# Host blocking (blocking instances plus void cells) must reproduce the loader-derived features.bin.
		var host: PackedByteArray = world.features.blocking_grid(PackedByteArray())
		for cell in metadata.get("voids", []):
			host[int(cell)] = 1
		check(host == blocking, entry.slug + " host feature blocking equals the prepared grid")
		for tick in range(5):
			world.step()
		loaded += 1
	print("MAPS %d / %d checks pass (%d maps, %.1f s)" % [checks - failures, checks, loaded, float(Time.get_ticks_msec() - started) / 1000.0])
	quit(0 if failures == 0 else 1)
