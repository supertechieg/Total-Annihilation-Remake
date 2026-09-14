extends SceneTree
## Compare cursor_projection.gd with the original 0x484b50 run by tools/native_screen_to_world.py.
const CursorProjection = preload("res://cursor_projection.gd")

func _initialize() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../local/cursor/native-screen-to-world.json")))
	if not data is Dictionary:
		printerr("Run tools/native_screen_to_world.py first")
		quit(1)
		return
	var checks := 0
	var failures := 0
	for scene: Dictionary in data.scenes:
		var heights := PackedByteArray(scene.heights.map(func(value): return int(value)))
		for call: Array in scene.calls:
			var actual: Array = CursorProjection.screen_to_world(heights, int(scene.cells_w), int(scene.cells_h), int(scene.map_w), int(scene.map_h), int(scene.sea), int(call[0]), int(call[1]))
			var expected := [int(call[2]), int(call[3]), int(call[4])]
			checks += 1
			if actual != expected:
				failures += 1
				if failures <= 8:
					printerr("sx=%d sy=%d map=%dx%d sea=%d expected %s got %s" % [int(call[0]), int(call[1]), int(scene.map_w), int(scene.map_h), int(scene.sea), expected, actual])
	print("SCREEN_TO_WORLD_NATIVE %d / %d checks match" % [checks - failures, checks])
	quit(0 if failures == 0 and checks > 0 else 1)
