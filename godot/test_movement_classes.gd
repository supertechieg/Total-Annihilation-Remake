extends SceneTree
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
func _initialize() -> void:
	var catalog := Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	var world := World.new(catalog, Navigation.new(64, 64, heights, 32), Vector2(128, 128))
	var checks: Array = [catalog.movement("armcom").maxwaterdepth == 100,
		catalog.movement("armflash").maxwaterdepth == 12,
		catalog.movement("armcv").footprintx == 3,
		world.unit_navigation("armcom").passable(Vector2i(32, 32)),
		not world.unit_navigation("armflash").passable(Vector2i(32, 32)),
		world.unit_navigation("armpt").passable(Vector2i(32, 32))]
	var dry := World.new(catalog, Navigation.new(64, 64, heights, 0), Vector2(128, 128))
	checks.append(not dry.unit_navigation("armpt").passable(Vector2i(32, 32)))
	checks.append(dry.unit_navigation("armflash").passable(Vector2i(32, 32)))
	print("MOVEMENT_CLASSES %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
