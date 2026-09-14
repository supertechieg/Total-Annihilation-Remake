extends VBoxContainer
## Picture build menu: the original builder GUI pages (guis/<builder><page>.gui plus download menu entries) shown as
## 64x64 unit-picture buttons in their 2x3 slots, with previous/next page controls. Unverified units stay visible but
## disabled, matching the dropdown gating.
signal unit_chosen(type: String)

var catalog: RefCounted
var supported: Callable
var pages: Array = []
var page := 0
var builder := ""
var grid: GridContainer
var page_label: Label
var textures: Dictionary = {}

func setup(source: RefCounted, is_supported: Callable) -> void:
	catalog = source
	supported = is_supported
	grid = GridContainer.new()
	grid.columns = 2
	add_child(grid)
	var row := HBoxContainer.new()
	var previous := Button.new()
	previous.text = "Prev"
	previous.pressed.connect(func() -> void: turn(-1))
	var next := Button.new()
	next.text = "Next"
	next.pressed.connect(func() -> void: turn(1))
	page_label = Label.new()
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(previous)
	row.add_child(page_label)
	row.add_child(next)
	add_child(row)

func show_builder(type: String) -> void:
	builder = type
	pages = catalog.index.get("build_pages", {}).get(type, [])
	page = 0
	visible = not pages.is_empty()
	render()

func turn(step: int) -> void:
	if pages.is_empty():
		return
	page = posmod(page + step, pages.size())
	render()

func picture(type: String) -> Texture2D:
	if not textures.has(type):
		var path = catalog.index.get("unit_pictures", {}).get(type)
		var image: Image = Image.load_from_file(catalog.root.path_join(str(path))) if path != null else null
		textures[type] = ImageTexture.create_from_image(image) if image != null else null
	return textures[type]

## Six slots row-major; empty slots are blank spacers so buttons keep their GUI positions.
func render() -> void:
	for child in grid.get_children():
		# Detach now: queue_free alone would leave the old buttons in the grid until the frame ends.
		grid.remove_child(child)
		child.queue_free()
	if pages.is_empty():
		return
	var slots: Array = [null, null, null, null, null, null]
	for entry: Dictionary in pages[page]:
		@warning_ignore("integer_division")
		var slot := clampi((int(entry.y) - 27) / 64, 0, 2) * 2 + (1 if int(entry.x) >= 64 else 0)
		slots[slot] = str(entry.unit)
	for type in slots:
		if type == null:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(64, 64)
			grid.add_child(spacer)
			continue
		var button := TextureButton.new()
		button.texture_normal = picture(type)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(64, 64)
		button.tooltip_text = str(catalog.definition(type).get("name", type))
		button.set_meta("unit", type)
		var allowed: bool = supported.call(type)
		button.disabled = not allowed
		button.modulate = Color.WHITE if allowed else Color(0.45, 0.45, 0.45)
		button.pressed.connect(func() -> void: unit_chosen.emit(type))
		grid.add_child(button)
	page_label.text = "%d / %d" % [page + 1, pages.size()]
