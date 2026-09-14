extends RefCounted
const Grid = preload("res://collision_grid.gd")
const Bounds = preload("res://unit_bounds.gd")
const Projectile = preload("res://projectile_collision.gd")
const Heights = preload("res://terrain_heights.gd")
var grid: RefCounted
var records: Dictionary = {}
var terrain: Dictionary = {}

## Weapon flag bits consulted by 0x49b090's terrain branch, from the loader's TDF mapping.
static func collision_flags(definition: Dictionary) -> int:
	return (Projectile.UNITS_ONLY if int(definition.get("unitsonly", "0")) & 1 else 0) \
		| (Projectile.GROUND_BOUNCE if int(definition.get("groundbounce", "0")) & 1 else 0) \
		| (Projectile.WATER_WEAPON if int(definition.get("waterweapon", "0")) & 1 else 0)

## Native terrain/feature/water test at the projectile endpoint. Updates velocity and feature cache in place.
## Map features are not yet supplied (Comet Catcher's are all height 0) and the map lava flag is taken as clear.
func terrain_impact(world: RefCounted, projectile: Dictionary, flags: int) -> bool:
	var cell := projectile_cell(projectile.position_raw)
	if cell < 0:
		return false
	if terrain.is_empty():
		terrain = Heights.prepare(world.navigation.heights, world.navigation.width, world.navigation.height)
	var contact := Projectile.terrain_contact({"flags": flags, "position": projectile.position_raw,
		"cell": {"low": int(terrain.low[cell]), "high": int(terrain.high[cell]), "code": 0xffff},
		"anchor_code": 0xffff, "feature_count": 0, "feature_heights": [], "sea": world.navigation.sea_level, "lava": 0,
		"velocity_y": int(projectile.velocity_raw[1]), "cache": projectile.get("terrain_cache", [-32768, -32768])})
	projectile.terrain_cache = contact.cache
	if int(contact.velocity_y) != int(projectile.velocity_raw[1]):
		projectile.velocity_raw[1] = int(contact.velocity_y)
	return bool(contact.impact)

func projectile_cell(position_raw: Array) -> int:
	return Projectile.cell_index(position_raw, grid.width, grid.depth)

func target_at(world: RefCounted, position_raw: Array, owner: int) -> int:
	var cell := projectile_cell(position_raw)
	if cell < 0:
		return 0
	var occupants: Array = []
	for id_value in grid.cells[cell]:
		var id := int(id_value)
		if id == 0 or not records.has(id) or not world.units.has(id):
			occupants.append({"id": 0, "owner": 0, "bottom": 0, "top": 0})
			continue
		var record: Dictionary = records[id]
		occupants.append({"id": id, "owner": int(world.units[id].get("team", 0)),
			"bottom": int(record.position_raw[1]) + int(record.bounds.lower[1]),
			"top": int(record.position_raw[1]) + int(record.bounds.upper[1])})
	return Projectile.unit_target(int(position_raw[1]), owner, occupants)

func _init(width: int, depth: int) -> void:
	grid = Grid.new(width, depth)

static func decode_yard(text: String, count: int) -> Array:
	var codes := {".": 0, "C": 0x35, "G": 0x8f, "O": 0x2b, "Y": 0x31,
		"c": 0x2d, "f": 0x6f, "o": 0x2f, "w": 0x37, "y": 0x29}
	var compact := text.replace(" ", "").replace("\n", "").replace("\r", "").replace("\t", "")
	var result: Array = []
	for index in range(count):
		var symbol := compact[mini(index, compact.length() - 1)] if not compact.is_empty() else "o"
		result.append(int(codes.get(symbol, 0)))
	return result

func sync_unit(world: RefCounted, id: int) -> void:
	var unit: Dictionary = world.units[id]
	var fields: Dictionary = world.catalog.definition(unit.type)
	# Only current ground-unit integration is supported; flight/submersion slot changes remain.
	if int(fields.get("canfly", "0")) != 0:
		return
	var position := [roundi(unit.position.x * 65536.0),
		roundi(world.navigation.height_at(unit.position) * 65536.0), roundi(unit.position.y * 65536.0)]
	var opened: bool = world.scripts.has(id) and int(world.scripts[id].values.get(18, 0)) != 0
	if not records.has(id):
		var movement: Dictionary = world.catalog.movement(unit.type)
		var size := Vector2i(int(movement.get("footprintx", "1")), int(movement.get("footprintz", "1")))
		var yard: Array = decode_yard(str(fields.get("yardmap", "")), size.x * size.y) if int(fields.get("bmcode", "1")) == 0 else []
		var rect := Grid.unit_rect([position[0], position[2]], size)
		records[id] = {"rect": rect, "slot": 0, "position_raw": position, "yard": yard, "yard_open": opened,
			"replaceable": false, "flags": 1 | (0x20000000 if not yard.is_empty() else 0),
			"bounds": Bounds.from_unit(world.catalog.load_unit(unit.type), movement)}
		records[id].inserted = grid.insert_unit(id, rect, 0, records, yard, opened)
		return
	var record: Dictionary = records[id]
	if record.yard_open != opened:
		grid.remove_unit(id, record.rect, record.slot, records, record.inserted, record.yard)
		record.yard_open = opened
		record.inserted = grid.insert_unit(id, record.rect, record.slot, records, record.yard, opened)
	grid.move_unit(id, position, 0, records)

func sync(world: RefCounted) -> void:
	for id: int in world.units:
		sync_unit(world, id)

func remove_unit(id: int) -> void:
	if not records.has(id):
		return
	var record: Dictionary = records[id]
	grid.remove_unit(id, record.rect, record.slot, records, record.inserted, record.yard)
	records.erase(id)
