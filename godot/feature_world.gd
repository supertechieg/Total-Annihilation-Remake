extends RefCounted
## Map feature grid: cell codes (+8), continuation offsets (+10 row, +11 column), owner nibble and feature instances.
## Placement follows 0x423c50, removal 0x4246b0 and corpse selection 0x486360. See analysis/WRECKAGE.md.
const NONE := 0xffff
const CONTINUATION := 0xfffe
var width: int
var height: int
var catalog: RefCounted
var codes := PackedInt32Array()
var rows := PackedByteArray()
var columns := PackedByteArray()
var owners := PackedByteArray()
## Feature names by index (the definition table); codes store these indices.
var names: Array = []
var name_index: Dictionary = {}
## Instances keyed by anchor cell: {name, cell, position_raw, health, metal, energy, owner}.
var instances: Dictionary = {}
var revision := 0

func _init(w: int, h: int, source: RefCounted) -> void:
	width = w
	height = h
	catalog = source
	codes.resize(w * h)
	codes.fill(NONE)
	rows.resize(w * h)
	columns.resize(w * h)
	owners.resize(w * h)

var feature_heights: Array = []

func index_of(name: String) -> int:
	name = name.to_lower()
	if not name_index.has(name):
		name_index[name] = names.size()
		names.append(name)
		feature_heights.append(int(catalog.feature(name).get("height", 0)))
	return int(name_index[name])

func anchor_of(cell: int) -> int:
	if cell < 0 or cell >= codes.size():
		return -1
	if codes[cell] == CONTINUATION:
		return cell - (int(rows[cell]) * width + int(columns[cell]))
	return cell

## 0x4246b0: clear the feature covering a cell. Indestructible features refuse unless forced.
func remove(cell: int, force := false) -> bool:
	var anchor := anchor_of(cell)
	if anchor < 0 or codes[anchor] > 0xfffa:
		return false
	var definition: Dictionary = catalog.feature(names[codes[anchor]])
	if not force and bool(definition.get("indestructible", false)):
		return false
	var ax := anchor % width
	var az := anchor / width
	codes[anchor] = NONE
	for dz in range(int(definition.get("footprintz", 0))):
		for dx in range(int(definition.get("footprintx", 0))):
			var covered := (az + dz) * width + ax + dx
			if covered < codes.size() and codes[covered] == CONTINUATION:
				codes[covered] = NONE
	instances.erase(anchor)
	revision += 1
	return true

## 0x423c50: place a feature with its anchor at cell (x, z). Returns the anchor cell or -1.
func place(name: String, x: int, z: int, position_raw = null, owner := 0) -> int:
	var definition: Dictionary = catalog.feature(name)
	if definition.is_empty():
		return -1
	var footprint_x := int(definition.footprintx)
	var footprint_z := int(definition.footprintz)
	if x < 0 or z < 0 or x + footprint_x > width or z + footprint_z > height:
		return -1
	for dz in range(footprint_z):
		for dx in range(footprint_x):
			var covered := (z + dz) * width + x + dx
			if codes[covered] != NONE and not remove(covered):
				return -1
	var anchor := z * width + x
	var feature_index := index_of(name)
	codes[anchor] = feature_index
	owners[anchor] = owner & 0xf
	for dz in range(footprint_z):
		for dx in range(footprint_x):
			if dx != 0 or dz != 0:
				var covered := (z + dz) * width + x + dx
				codes[covered] = CONTINUATION
				rows[covered] = dz
				columns[covered] = dx
	if position_raw == null:
		# Default instance position: footprint centre on the grid, 0x80000 per half cell.
		position_raw = [(footprint_x + x * 2) * 0x80000, 0, (footprint_z + z * 2) * 0x80000]
	instances[anchor] = {"name": name.to_lower(), "cell": anchor, "position_raw": position_raw, "owner": owner & 0xf,
		"health": int(definition.damage), "metal": float(definition.metal), "energy": float(definition.energy)}
	revision += 1
	return anchor

## 0x486360: corpse type 1 places the definition corpse; each further step follows featuredead.
func place_corpse(corpse: String, corpse_type: int, x: int, z: int, position_raw: Array, owner: int) -> int:
	var name := corpse.to_lower()
	var steps := corpse_type
	while steps >= 2:
		if name.is_empty() or catalog.feature(name).is_empty():
			return -1
		name = str(catalog.feature(name).get("featuredead", ""))
		steps -= 1
	if name.is_empty() or catalog.feature(name).is_empty():
		return -1
	return place(name, x, z, position_raw, owner)

## Nonzero cells where a blocking feature's anchor or continuation lies (0x47de60 feature branch).
func blocking_grid(base: PackedByteArray) -> PackedByteArray:
	var result := base.duplicate() if base.size() == codes.size() else PackedByteArray()
	if result.is_empty():
		result.resize(codes.size())
	for anchor: int in instances:
		var definition: Dictionary = catalog.feature(instances[anchor].name)
		if not bool(definition.get("blocking", false)):
			continue
		var ax := anchor % width
		var az := anchor / width
		for dz in range(int(definition.footprintz)):
			for dx in range(int(definition.footprintx)):
				result[(az + dz) * width + ax + dx] = 1
	return result

## Terrain-contact inputs for projectile_collision.terrain_contact at a cell.
func contact_fields(cell: int) -> Dictionary:
	var code := int(codes[cell]) if cell >= 0 and cell < codes.size() else NONE
	var anchor := anchor_of(cell)
	var anchor_code := int(codes[anchor]) if code == CONTINUATION and anchor >= 0 else NONE
	return {"code": code, "anchor_code": anchor_code, "feature_count": names.size(), "feature_heights": feature_heights}
