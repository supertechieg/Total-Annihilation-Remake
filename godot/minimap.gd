extends Control
## Sidebar minimap: the prepared map image, unit dots in team colours, the main view rectangle, and click/drag to move
## the view. Provisional presentation; the original's LOS shading and radar-dot rules (0x466c20/0x466dc0) come with the
## visibility checkpoints.
signal view_requested(world_point: Vector2)

var image: Texture2D
var world_size := Vector2(1, 1)
var units: Dictionary = {}
var view_rect := Rect2()
var local_team := 0
const TEAM_COLOURS := [Color("4f8cff"), Color("ff4b3e"), Color("f2d24b"), Color("58d36a")]

func setup(texture: Texture2D, size_in_world: Vector2) -> void:
	image = texture
	world_size = size_in_world
	var fit := minf(280.0 / world_size.x, 280.0 / world_size.y)
	custom_minimum_size = Vector2(world_size.x * fit, world_size.y * fit)
	mouse_filter = Control.MOUSE_FILTER_STOP

## Area of the control covered by the map image (aspect preserved, centred).
func map_area() -> Rect2:
	var scale := minf(size.x / world_size.x, size.y / world_size.y)
	var extent := world_size * scale
	return Rect2((size - extent) * 0.5, extent)

func to_minimap(point: Vector2) -> Vector2:
	var area := map_area()
	return area.position + point / world_size * area.size

func to_world(point: Vector2) -> Vector2:
	var area := map_area()
	return ((point - area.position) / area.size * world_size).clamp(Vector2.ZERO, world_size)

func refresh(source_units: Dictionary, main_view: Rect2) -> void:
	units = source_units
	view_rect = main_view
	queue_redraw()

func _draw() -> void:
	var area := map_area()
	if image != null:
		draw_texture_rect(image, area, false)
	else:
		draw_rect(area, Color("202a20"))
	for unit: Dictionary in units.values():
		var team := int(unit.get("team", 0))
		var colour: Color = TEAM_COLOURS[team % TEAM_COLOURS.size()]
		var dot := to_minimap(unit.position)
		draw_rect(Rect2(dot - Vector2(1.5, 1.5), Vector2(3, 3)), colour)
	var top_left := to_minimap(view_rect.position)
	var bottom_right := to_minimap(view_rect.end)
	draw_rect(Rect2(top_left, bottom_right - top_left).intersection(area), Color(1, 1, 1, 0.9), false, 1.0)
	draw_rect(area, Color(0, 0, 0, 0.8), false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		view_requested.emit(to_world(event.position))
		accept_event()
