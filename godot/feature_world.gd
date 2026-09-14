extends RefCounted
## Map feature grid: cell codes (+8), continuation offsets (+10 row, +11 column), owner nibble and feature instances.
## Placement follows 0x423c50, removal 0x4246b0 and corpse selection 0x486360. See analysis/WRECKAGE.md.
const FeatureDamage = preload("res://feature_damage.gd")
const NONE := 0xffff
const CONTINUATION := 0xfffe
const VOID := 0xfffc
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
## Terrain height bytes (cell +4) for default instance heights and the 2D-feature splash distance.
var heights := PackedByteArray()
var depth: int
## Per definition index: {footprintx, footprintz, damage, flags} with the +0xfe flag bits used by feature damage.
var damage_definitions: Array = []

func _init(w: int, h: int, source: RefCounted) -> void:
	width = w
	height = h
	depth = h
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
		var definition: Dictionary = catalog.feature(name)
		damage_definitions.append({"footprintx": int(definition.get("footprintx", 0)), "footprintz": int(definition.get("footprintz", 0)), "damage": int(definition.get("damage", 0)),
			"flags": (0x1 if str(definition.get("object", "")).is_empty() else 0) | (0x10 if definition.get("flamable", false) else 0) | (0x40 if definition.get("blocking", false) else 0)
				| (0x80 if definition.get("reclaimable", false) else 0) | (0x200 if definition.get("indestructible", false) else 0)})
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
		# 0x423e3d default instance position: footprint centre (0x80000 per half cell) at the 0x485070 terrain height.
		var px := (footprint_x + x * 2) << 19
		var pz := (footprint_z + z * 2) << 19
		position_raw = [px, FeatureDamage.height(heights, width, height, px, pz) << 16 if not heights.is_empty() else 0, pz]
	# Instance +0x26 damage restarts at zero; 2D features accumulate damage in the anchor cell word instead.
	instances[anchor] = {"name": name.to_lower(), "cell": anchor, "position_raw": position_raw, "owner": owner & 0xf,
		"health": int(definition.damage), "metal": float(definition.metal), "energy": float(definition.energy), "damage_taken": 0}
	revision += 1
	return anchor

## 0x423550/0x423710: remove a feature and place its featurereclamate (reclaimed) or featuredead (destroyed)
## at the same anchor and instance position with owner 10. Returns the new anchor, or -1 when nothing replaces it.
func replace(cell: int, reclaimed: bool) -> int:
	var anchor := anchor_of(cell)
	if not instances.has(anchor):
		return -1
	var instance: Dictionary = instances[anchor]
	var successor := str(catalog.feature(instance.name).get("featurereclamate" if reclaimed else "featuredead", ""))
	if not remove(anchor):
		return -1
	if successor.is_empty() or catalog.feature(successor).is_empty():
		return -1
	# 0x4237ae: features without an instance record place their successor at the default position.
	var keep_position: bool = int(damage_definitions[index_of(instance.name)].flags) & 0x1 == 0
	return place(successor, anchor % width, anchor / width, instance.position_raw if keep_position else null, 10)

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

## Grid interface for FeatureDamage.splash. Anchors of features with an object carry the instance flag and use
## the anchor cell as the instance index; 2D anchors expose their damage accumulator as the cell word.
func code_at(cell: int) -> int:
	return int(codes[cell])

func has_instance_record(cell: int) -> bool:
	return codes[cell] < 0xfffb and instances.has(cell) and int(damage_definitions[codes[cell]].flags) & 0x1 == 0

func word_at(cell: int) -> int:
	if codes[cell] == CONTINUATION:
		return int(rows[cell]) | (int(columns[cell]) << 8)
	if has_instance_record(cell):
		return cell
	return int(instances[cell].damage_taken) if instances.has(cell) else 0

func bits_at(cell: int) -> int:
	return 1 if has_instance_record(cell) else 0

func set_word(cell: int, value: int) -> void:
	if instances.has(cell):
		instances[cell].damage_taken = value

func definition_of(code: int) -> Dictionary:
	return damage_definitions[code]

func instance_position(index: int) -> Array:
	return instances[index].position_raw

func instance_anchor(index: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % width, index / width)

func instance_damage(index: int) -> int:
	return int(instances[index].damage_taken)

func set_instance_damage(index: int, value: int) -> void:
	instances[index].damage_taken = value