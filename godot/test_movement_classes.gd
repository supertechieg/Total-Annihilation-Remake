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
	var differing := 0
	for type: String in catalog.index.units:
		var fields := catalog.definition(type)
		var movement := catalog.movement(type)
		if int(fields.get("footprintx", 0)) == int(movement.footprintx) and int(fields.get("footprintz", 0)) == int(movement.footprintz):
			continue
		differing += 1
		var id := dry.add_unit(type, Vector2(512, 512), 0)
		var size := Vector2i(int(movement.footprintx), int(movement.footprintz))
		checks.append(dry.collision.records[id].rect.size == size)
		checks.append(dry.collision.records[id].bounds.upper[0] == size.x * 524288)
		checks.append(dry.footprint(type, Vector2(512, 512)).size == Vector2(size) * 16)
		dry.remove_unit(id)
	checks.append(differing == 13)
	# A submerged ridge can exceed the dry-land slope limit of a movement class.
	var ridge := heights.duplicate()
	ridge[32 * 64 + 32] = 40
	var submerged := Navigation.new(64, 64, ridge, 64, 12, 10000, Vector2i(2, 2), -10000, 255)
	var exposed := Navigation.new(64, 64, ridge, 0, 12, 10000, Vector2i(2, 2), -10000, 255)
	checks.append(submerged.passable(Vector2i(32, 32)))
	checks.append(not exposed.passable(Vector2i(32, 32)))
	print("MOVEMENT_CLASSES %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
