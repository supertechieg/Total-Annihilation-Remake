extends SceneTree
## Minimap coordinate mapping: aspect-preserving fit, world <-> minimap round trip, clamping and view requests.
const Minimap = preload("res://minimap.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var minimap = Minimap.new()
	minimap.setup(null, Vector2(4000, 2000))
	check(minimap.custom_minimum_size == Vector2(280, 140), "The minimap fits the map into 280 px keeping its aspect")
	minimap.size = Vector2(300, 300)
	var area: Rect2 = minimap.map_area()
	check(area.size == Vector2(300, 150) and area.position == Vector2(0, 75), "A wide map is centred vertically in a square control")
	var point := Vector2(1234, 567)
	check(minimap.to_world(minimap.to_minimap(point)).distance_to(point) < 0.01, "World to minimap and back round-trips")
	check(minimap.to_world(Vector2(-50, 500)) == Vector2(0, 2000), "Clicks outside the image clamp to the map edge")
	var requested: Array = []
	minimap.view_requested.connect(func(world_point: Vector2) -> void: requested.append(world_point))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = minimap.to_minimap(Vector2(2000, 1000))
	minimap._gui_input(click)
	check(requested.size() == 1 and requested[0].distance_to(Vector2(2000, 1000)) < 0.01, "A left click requests the view at that world point")
	minimap.free()
	print("MINIMAP %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
