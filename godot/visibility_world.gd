extends RefCounted
## VisibilityWorld (preload by path): per-player line-of-sight refcount grids, the shared mapped ("explored") word grid,
## and the event-driven LOS stamping of the original game, verified against the original routines by
## tools/native_los_stamp.py + godot/compare_native_los_stamp.gd (oracle O3).
##
## Original routines reproduced here (addresses in TotalA.exe):
##   stamp add 0x482270, stamp remove 0x481d50, stamp map 0x481930            -> _stamp_count(+1) / _stamp_count(-1) / _stamp_map
##   per-unit update 0x4827b0 -> ctx update 0x4825b0                          -> update_unit / _update_ctx
##   create 0x482ac0                                                           -> create_unit
##   death: temp LOS gate 0x486706/0x48672a -> 0x482910, removal gate 0x486832 -> 0x482090   -> kill_unit
##   temporary LOS add 0x482910, expiry 0x482130                               -> add_temp_los / expire_temp_los
##   full rebuild 0x4816a0(resetMapping)                                       -> rebuild
##
## World-agnostic API: units are Dictionaries owned by the caller. Keys read:
##   owner:int (player slot, the record game+0x1b63+slot*0x14b), pos16:Array[int] [x, y, z] raw 16.16 (unit+0x6a/+0x6e/+0x72;
##   y is the unit's own altitude), sight:int (def+0x202, used as int16), eye_bonus:int (def+0x170, low byte used),
##   unit_flags:int (unit+0x110; only bit 0x10000000 is read, by kill_unit).
## Keys written (the unit's LOS registration): los_col, los_row (int16 unit+0x7a/+0x7c), los_slot (byte unit+0xf8:
##   circular = vismask frame index, true = eye height, 0 = not registered in true mode).
## A new unit must start with los_col = los_row = los_slot = 0 (0x485a40 zeroes +0x7a, +0x7c, +0xf8).
##
## Native quirks kept on purpose (confirmed by the oracle unless marked as an assumption):
## * The ctx y is raised to (sea_level + 1) << 16 before any use (0x4827b0/0x482090/0x482ac0/0x4816a0/0x482910).
## * True mode early-out: same centre and |los_slot - vh| <= 5. Create and rebuild zero los_slot but keep the stored
##   origin, so a unit whose centre equals the stale origin with vh <= 5 is never registered; its death still
##   decrements (0x482090 does not test the slot) -> refcount underflow to 0xFF.
## * True mode stores the new centre before the height-grid bounds test; out of bounds stores los_slot = 0.
## * True mode removal only if the old slot != 0 and the flags word read at ctx-update entry has LOS on (bit 2);
##   adds use the current flags. Mapping (bit 1) gates the map stamp in 0x4825b0, but circular create/rebuild/temp map
##   unconditionally.
## * Add/remove clear overlay bit 8 and request the minimap terrain redraw (game+0x142f1 |= 4) whenever the stamp owner's
##   index equals the local player, before any bounds test; map does so only when a mapped bit actually changed.
## * Circular stamps clip against the MAP half size (trunc(map_w/2), trunc(map_h/2)) and index grids with the record's
##   width; true stamps clip against the height grid; the true map stamp indexes the mapped words with the map half width.
## * Ray steps outside the height grid still advance the step counter; steps are s16(centre + offset).
## * Table index = min(max(trunc(sight/32), 0), numtables - 1), then 0x433500 uses table k - 1: sight < 32 reads the
##   object before the table vector. ASSUMPTION: that object is treated as an empty ray vector (centre cell only), matching the
##   oracle's zeroed memory; the shipped game's heap content there is unknown (see undefined_table_reads).
## * Removal in circular mode looks the frame up by the stored slot: a slot >= frame count (left by true mode after a
##   LOSType switch, typically a temporary entry) makes 0x4b7f30 return NULL and the original crashes reading it.
##   This is reported as `fault` (string) and the world must be considered dead, as the game would be.
## * Temporary LOS entries keep a 20-slot backing store: 0x482910 never initialises the entry origin (+0x20), and
##   expiry compaction (std::remove_if) leaves the tail slots untouched, so stale origins are reproduced exactly.
##   ASSUMPTION: the backing store starts zeroed (the game allocates it with malloc(0x2d0) at 0x481519, contents unknown).
##   Rebuilds do not re-add temporary entries; their expiry later decrements (underflow).

const LosTables = preload("res://los_tables.gd")

const FLAG_MAPPING := 1
const FLAG_LOS := 2
const FLAG_TRUE := 4
const FLAG_OVERLAY := 8
const TEMP_CAPACITY := 20
const PLAYER_SLOTS := 10
const TEMP_FLAG_ALIVE := 0x10000000

var flags := 0  # word game+0x14281
var map_w := 0  # game+0x14233 (16-px cells)
var map_h := 0  # game+0x14237
var half_w := 0  # trunc(map_w / 2)
var half_h := 0
var los_pad := 0
var sea_level := 0  # byte game+0x1427f
var local_player := 0  # byte game+0x2a43
var tick := 0  # u32 game+0x38a47
var mapped := PackedByteArray()  # game+0x14273: words, bit (1 << player index)
var height: Dictionary = {}  # LosHeightGrid.build result {w2, h2, pad, grid}
var tables: Array = []  # LosTables.parse result
var frames: Array = []  # [{w, h, xoff, yoff, transparent, pixels}]
var players: Array = []  # slot -> null or {index, type, los: PackedByteArray, w2, h2, pad}
var temp_entries: Array = []  # 20 backing slots
var temp_count := 0
var redraw_dirty := false  # game+0x142f1 bit 4 as handed to the minimap terrain redraw 0x466c20
var minimap_terrain_calls := 0  # 0x466c20 calls from rebuild
var minimap_dots_calls := 0  # 0x466dc0 calls from rebuild
var undefined_table_reads := 0
var fault = null


static func s16(v: int) -> int:
	return ((v & 0xFFFF) ^ 0x8000) - 0x8000

static func s32(v: int) -> int:
	return ((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000


## Vismask frames from local/visibility/vismasks.json ("frames": width/height/xoff/yoff/transparent/pixels_base64).
static func frames_from_json(vismasks: Dictionary) -> Array:
	var result := []
	for frame: Dictionary in vismasks.frames:
		result.append({"w": int(frame.width), "h": int(frame.height), "xoff": int(frame.xoff), "yoff": int(frame.yoff),
			"transparent": int(frame.transparent), "pixels": Marshalls.base64_to_raw(frame.pixels_base64)})
	return result


func setup(p_map_w: int, p_map_h: int, p_sea_level: int, p_height: Dictionary, p_tables: Array, p_frames: Array) -> void:
	map_w = p_map_w
	map_h = p_map_h
	half_w = int(map_w / 2)
	half_h = int(map_h / 2)
	los_pad = (half_w * half_h + 7) & ~7
	sea_level = p_sea_level & 0xFF
	height = p_height
	tables = p_tables
	frames = p_frames
	mapped = PackedByteArray()
	mapped.resize((map_w * map_h * 2) >> 2)
	players = []
	players.resize(PLAYER_SLOTS)
	temp_entries = []
	for i in range(TEMP_CAPACITY):
		temp_entries.append(_blank_temp())
	temp_count = 0
	fault = null


## A player record: type (+0x73: 1/2/3 are refilled by rebuild), index (+0x146, the mapped bit and local-player id).
func add_player(slot: int, index: int, type: int) -> void:
	var los := PackedByteArray()
	los.resize(los_pad)
	players[slot] = {"index": index, "type": type, "los": los, "w2": half_w, "h2": half_h, "pad": los_pad}


static func _blank_temp() -> Dictionary:
	return {"owner": -1, "los_col": 0, "los_row": 0, "sight": 0, "eye_bonus": 0, "los_slot": 0, "pos16": [0, 0, 0], "expiry": 0}


func is_visible_cell(player_slot: int, col: int, row: int) -> bool:
	var rec: Dictionary = players[player_slot]
	return rec.los[row * rec.w2 + col] != 0

func mapped_word(index: int) -> int:
	return mapped[index * 2] | (mapped[index * 2 + 1] << 8)


# ---------------------------------------------------------------- ctx
## ctx = {holder: Dictionary with los_col/los_row/los_slot, owner, sight (int16), eye (u8), pos: [x, y, z] with y clamped}
func _ctx(holder: Dictionary, owner: int, sight: int, eye: int, pos16: Array) -> Dictionary:
	var floor_y := (sea_level + 1) << 16
	var y := s32(int(pos16[1]))
	return {"holder": holder, "owner": owner, "sight": s16(sight), "eye": eye & 0xFF,
		"pos": [s32(int(pos16[0])), floor_y if y < floor_y else y, s32(int(pos16[2]))]}

func _unit_ctx(unit: Dictionary) -> Dictionary:
	return _ctx(unit, int(unit.owner), int(unit.sight), int(unit.eye_bonus), unit.pos16)


func _frame_for_sight(sight: int) -> int:
	var f := int(s16(sight) / 32) - 5
	if f < 0:
		return 0
	if f >= frames.size():
		return frames.size() - 1
	return f

## Circular origin (0x4825b0 0x4826e1.., 0x482ac0, 0x4816a0, 0x482910): trunc(x / 2^21) - xoff,
## trunc(z / 2^21) - trunc(int16(y >> 16) / 64) - yoff.
func _circular_origin(pos: Array, f: int) -> Vector2i:
	var frame: Dictionary = frames[f]
	var cx := int(int(pos[0]) / 2097152) - int(frame.xoff)
	var cy := int(int(pos[2]) / 2097152) - int(s16(int(pos[1]) >> 16) / 64) - int(frame.yoff)
	return Vector2i(cx, cy)

func _table_rays(sight: int):
	var k := int(s16(sight) / 32)
	if k < 0:
		k = 0
	var count := s16(tables.size())
	if k >= count - 1:
		k = count - 1
	var rays = LosTables.rays_for(tables, k)
	if rays == null:
		undefined_table_reads += 1
		return []
	return rays

func _in_height_grid(col: int, row: int) -> bool:
	return (col & 0xFFFFFFFF) < int(height.w2) and (row & 0xFFFFFFFF) < int(height.h2)

func _request_redraw_if_local(owner: int) -> void:
	if int(players[owner].index) == local_player:
		flags &= 0xFFF7
		redraw_dirty = true


# ---------------------------------------------------------------- stamps
## 0x482270 (delta +1) and 0x481d50 (delta -1).
func _stamp_count(ctx: Dictionary, delta: int) -> void:
	var owner: int = ctx.owner
	_request_redraw_if_local(owner)
	var rec: Dictionary = players[owner]
	var los: PackedByteArray = rec.los
	var stride: int = rec.w2
	var holder: Dictionary = ctx.holder
	var col := s16(int(holder.los_col))
	var row := s16(int(holder.los_row))
	if flags & FLAG_TRUE:
		if not _in_height_grid(col, row):
			return
		var rays: Array = _table_rays(ctx.sight)
		var at := row * stride + col
		los[at] = (los[at] + delta) & 0xFF
		var vh := int(holder.los_slot) & 0xFF
		var grid: PackedByteArray = height.grid
		var hw: int = height.w2
		for ray: PackedInt32Array in rays:
			var num := -1
			var den := 0
			var steps := ray.size() >> 1
			for i in range(1, steps + 1):
				var x := s16(col + ray[(i - 1) * 2])
				var y := s16(row + ray[(i - 1) * 2 + 1])
				if not _in_height_grid(x, y):
					continue
				var e := (y * hw + x) * 2
				var lim := num * i
				if (grid[e] - vh) * den > lim:
					var cell := y * stride + x
					los[cell] = (los[cell] + delta) & 0xFF
					if (grid[e + 1] - vh) * den > lim:
						num = grid[e + 1] - vh
						den = i
	else:
		var f := int(holder.los_slot) & 0xFF
		if f >= frames.size():
			fault = "0x4b7f30 returned NULL: circular %s with slot %d >= %d frames" % ["add" if delta > 0 else "remove", f, frames.size()]
			return
		var frame: Dictionary = frames[f]
		var w: int = frame.w
		var h: int = frame.h
		var xend := half_w - col if col + w >= half_w else w
		var yend := half_h - row if row + h >= half_h else h
		var xstart := -col if col < 0 else 0
		var ystart := -row if row < 0 else 0
		if ystart >= yend or xstart >= xend:
			return
		var pixels: PackedByteArray = frame.pixels
		var transparent: int = frame.transparent
		for y in range(ystart, yend):
			var base := (row + y) * stride + col
			for x in range(xstart, xend):
				if pixels[y * w + x] != transparent:
					los[base + x] = (los[base + x] + delta) & 0xFF


func _touch_mapped(index: int, bit: int) -> bool:
	var word := mapped[index * 2] | (mapped[index * 2 + 1] << 8)
	if word & bit:
		return false
	word ^= bit
	mapped[index * 2] = word & 0xFF
	mapped[index * 2 + 1] = (word >> 8) & 0xFF
	return true

## 0x481930.
func _stamp_map(ctx: Dictionary) -> void:
	var owner: int = ctx.owner
	var index: int = players[owner].index
	var bit := (1 << (index & 31)) & 0xFFFF
	var holder: Dictionary = ctx.holder
	var col := s16(int(holder.los_col))
	var row := s16(int(holder.los_row))
	var changed := false
	if flags & FLAG_TRUE:
		if not _in_height_grid(col, row):
			return
		var rays: Array = _table_rays(ctx.sight)
		if _touch_mapped(row * half_w + col, bit):
			changed = true
		var vh := int(holder.los_slot) & 0xFF
		var grid: PackedByteArray = height.grid
		var hw: int = height.w2
		for ray: PackedInt32Array in rays:
			var num := -1
			var den := 0
			var steps := ray.size() >> 1
			for i in range(1, steps + 1):
				var x := s16(col + ray[(i - 1) * 2])
				var y := s16(row + ray[(i - 1) * 2 + 1])
				if not _in_height_grid(x, y):
					continue
				var e := (y * hw + x) * 2
				var lim := num * i
				if (grid[e] - vh) * den > lim:
					if _touch_mapped(y * half_w + x, bit):
						changed = true
					if (grid[e + 1] - vh) * den > lim:
						num = grid[e + 1] - vh
						den = i
	else:
		var frame: Dictionary = frames[_frame_for_sight(ctx.sight)]
		var w: int = frame.w
		var h: int = frame.h
		var xend := half_w - col if col + w >= half_w else w
		var yend := half_h - row if row + h >= half_h else h
		var xstart := -col if col < 0 else 0
		var ystart := -row if row < 0 else 0
		var pixels: PackedByteArray = frame.pixels
		var transparent: int = frame.transparent
		for y in range(ystart, yend):
			var base := (row + y) * half_w + col
			for x in range(xstart, xend):
				if pixels[y * w + x] != transparent:
					if _touch_mapped(base + x, bit):
						changed = true
	if changed and index == local_player:
		flags &= 0xFFF7
		redraw_dirty = true


# ---------------------------------------------------------------- ctx update 0x4825b0
func _update_ctx(ctx: Dictionary) -> void:
	var saved := flags
	var holder: Dictionary = ctx.holder
	var pos: Array = ctx.pos
	if flags & FLAG_TRUE:
		var col := s16(int(pos[0]) >> 16) >> 5
		var vh := int(ctx.eye) + s16(int(pos[1]) >> 16)
		vh = clampi(vh, 0, 255)
		var row := (s16(int(pos[2]) >> 16) - (vh >> 1)) >> 5
		var old_slot := int(holder.los_slot) & 0xFF
		if s16(int(holder.los_col)) == col and s16(int(holder.los_row)) == row and absi(old_slot - vh) <= 5:
			return
		if old_slot != 0 and (saved & FLAG_LOS):
			_stamp_count(ctx, -1)
			if fault != null:
				return
		holder.los_col = s16(col)
		holder.los_row = s16(row)
		if (col & 0xFFFFFFFF) < int(height.w2) and (row & 0xFFFFFFFF) < int(height.h2):
			holder.los_slot = vh
			if flags & FLAG_LOS:
				_stamp_count(ctx, 1)
			if flags & FLAG_MAPPING:
				_stamp_map(ctx)
		else:
			holder.los_slot = 0
	else:
		var f := _frame_for_sight(ctx.sight)
		var origin := _circular_origin(pos, f)
		if s16(int(holder.los_col)) == origin.x and s16(int(holder.los_row)) == origin.y and (int(holder.los_slot) & 0xFF) == f:
			return
		if flags & FLAG_LOS:
			_stamp_count(ctx, -1)
			if fault != null:
				return
			_store_circular(holder, origin, f)
			_stamp_count(ctx, 1)
		else:
			_store_circular(holder, origin, f)
		if flags & FLAG_MAPPING:
			_stamp_map(ctx)

func _store_circular(holder: Dictionary, origin: Vector2i, f: int) -> void:
	holder.los_col = s16(origin.x)
	holder.los_row = s16(origin.y)
	holder.los_slot = f & 0xFF

## Circular registration used by create 0x482ac0, rebuild 0x4816a0 and temp add 0x482910: add then map, no flag-1 test.
func _register_circular(ctx: Dictionary) -> void:
	var f := _frame_for_sight(ctx.sight)
	_store_circular(ctx.holder, _circular_origin(ctx.pos, f), f)
	_stamp_count(ctx, 1)
	_stamp_map(ctx)


# ---------------------------------------------------------------- public lifecycle
## 0x4827b0: call when the unit's footprint cell or low flag bits changed (0x48a9f0), or from the other callers.
func update_unit(unit: Dictionary) -> void:
	if fault != null:
		return
	_update_ctx(_unit_ctx(unit))

## 0x482ac0 (after 0x485a40 zeroed los_col/los_row/los_slot).
func create_unit(unit: Dictionary) -> void:
	if fault != null or not (flags & FLAG_LOS):
		return
	var ctx := _unit_ctx(unit)
	unit.los_slot = 0
	if flags & FLAG_TRUE:
		_update_ctx(ctx)
	else:
		_register_circular(ctx)

## Death path 0x486706..0x486845: temporary LOS for alive-flagged local units, then removal when LOS is on.
func kill_unit(unit: Dictionary) -> void:
	if fault != null:
		return
	if int(unit.get("unit_flags", TEMP_FLAG_ALIVE)) & TEMP_FLAG_ALIVE and int(players[int(unit.owner)].index) == local_player:
		add_temp_los(unit.pos16, s16(int(unit.sight)), s16(int(unit.eye_bonus)), 60)
		if fault != null:
			return
	if flags & FLAG_LOS:
		_stamp_count(_unit_ctx(unit), -1)  # 0x482090: no slot test

## 0x482910(pos, sight, eye, duration): owner is always the local player's record.
func add_temp_los(pos16: Array, sight: int, eye: int, duration: int) -> void:
	if fault != null or not (flags & FLAG_LOS) or temp_count >= TEMP_CAPACITY:
		return
	var entry: Dictionary = temp_entries[temp_count]
	entry.owner = local_player
	entry.sight = s16(sight)
	entry.eye_bonus = eye & 0xFF
	var ctx := _ctx(entry, local_player, sight, eye, pos16)
	entry.pos16 = (ctx.pos as Array).duplicate()
	entry.expiry = (tick + duration) & 0xFFFFFFFF
	entry.los_slot = 0
	if flags & FLAG_TRUE:
		_update_ctx(ctx)
	else:
		_register_circular(ctx)
	if fault != null:
		return
	temp_count += 1

func _temp_ctx(entry: Dictionary) -> Dictionary:
	return {"holder": entry, "owner": int(entry.owner), "sight": int(entry.sight), "eye": int(entry.eye_bonus), "pos": entry.pos16}

## 0x482130: once per frame after the tick batch. Uses the current mode and each entry's stored slot.
func expire_temp_los() -> void:
	if fault != null:
		return
	for i in range(temp_count):
		var entry: Dictionary = temp_entries[i]
		if int(entry.expiry) < tick:
			_stamp_count(_temp_ctx(entry), -1)
			if fault != null:
				return
	# std::remove_if with expiry < tick: kept entries are copied forward, tail slots keep their old contents.
	var first := -1
	for i in range(temp_count):
		if int(temp_entries[i].expiry) < tick:
			first = i
			break
	if first < 0:
		return
	var write := first
	for read in range(first + 1, temp_count):
		if not (int(temp_entries[read].expiry) < tick):
			var src: Dictionary = temp_entries[read]
			var copy := src.duplicate()
			copy.pos16 = (src.pos16 as Array).duplicate()
			temp_entries[write] = copy
			write += 1
	temp_count = write

## 0x4816a0(resetMapping). units: every unit with word +0xa6 != 0, index >= 1, in index order.
func rebuild(reset_mapping: bool, units: Array) -> void:
	if fault != null:
		return
	if reset_mapping:
		mapped.fill(0x00 if flags & FLAG_MAPPING else 0xFF)
	for slot in range(PLAYER_SLOTS):
		var rec = players[slot]
		if rec == null:
			continue
		var type: int = rec.type
		if (type == 1 or type == 2 or type == 3) and int(rec.index) != 10:
			var los: PackedByteArray = rec.los
			los.fill(0 if flags & FLAG_LOS else 1)
	if flags & FLAG_LOS:
		for unit: Dictionary in units:
			var ctx := _unit_ctx(unit)
			unit.los_slot = 0
			if flags & FLAG_TRUE:
				_update_ctx(ctx)
			else:
				_register_circular(ctx)
			if fault != null:
				return
	redraw_dirty = true
	flags &= 0xFFF7
	minimap_terrain_calls += 1
	minimap_dots_calls += 1


## Canonical text of the 20 temp slots, identical to the oracle's encoding.
func temp_canonical() -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in temp_entries:
		var pos: Array = entry.pos16
		parts.append("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [int(entry.owner), s16(int(entry.los_col)), s16(int(entry.los_row)),
			s16(int(entry.sight)), int(entry.eye_bonus) & 0xFF, int(entry.los_slot) & 0xFF, s32(int(pos[0])), s32(int(pos[1])),
			s32(int(pos[2])), int(entry.expiry) & 0xFFFFFFFF])
	return ";".join(parts)
