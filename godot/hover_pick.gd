extends RefCounted
## Original hover picking (TotalA.exe 0x48cd80 / 0x48c6a0 / 0x4cb650 / 0x4b6cc0 / 0x4c1320, visible list 0x48bae0,
## minimap blips 0x466dc0). Verified by tools/native_hover_pick.py + compare_native_hover_pick.gd. See HOVER_PICK.md.
##
## Plain-data inputs (all 16.16 values are signed 32-bit ints, "word" values are unsigned 16-bit):
##   unit  = {"type_id": word (+0xa6, 0 = empty slot), "index": word (+0xa8, the returned id),
##            "x","y","z": 16.16 position (+0x6a/+0x6e/+0x72),
##            "angles": [word +0x64, word +0x66, word +0x68]  (rotate (x,y) by [0], then (y,z) by [2], then (x,z) by [1]),
##            "owner": byte (+0xff), "flags110": dword (+0x110), "def_index": int into defs (or "def": Dictionary)}
##   def   = {"min": [x,y,z] 16.16 (+0x15e/+0x162/+0x166), "max": [x,y,z] (+0x16a/+0x16e/+0x172),
##            "size": [x,y,z] 16.16 (+0x176/+0x17a/+0x17e)}
##   model = root 3DO piece AFTER the loader's axis conversion 0x4cb590 (vertex x and z negated, piece offset x and z
##           negated): {"count": vertex count (+4, signed), "offset": [x,y,z] (+0x10..+0x18),
##           "vertices": [[x,y,z], ...] (+0x24, 12 bytes each)}. models is keyed by type_id (int or String key).
##   cam   = {"x": int, "y": int}  world pixels (game +0x1431f / +0x14323)
##   view  = {"left","top","right","bottom"} inclusive (game +0x37e27; the game uses 128, 32, W-1, H-33)
##   cells = {"w": int, "h": int, "heights": PackedByteArray or Array}  (game +0x14233/+0x14237, cell byte +4)
##   blip  = [word id, int sx, int sy]  (10-byte entries at game +0x14363, count +0x1436b)

const ANGLE_SCALE_BITS := 0x3F1921FB54442C5A  # qword 0x509ef8, about 2*pi/65536 (not exactly: 0x...2D18 would be)
const INT32_MIN := -2147483648
const NO_KEY := 0x7fff0000

static var _angle_scale := 0.0

static func s16(v: int) -> int:
	return ((v & 0xFFFF) ^ 0x8000) - 0x8000

static func s32(v: int) -> int:
	return ((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000

static func angle_scale() -> float:
	if _angle_scale == 0.0:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_s64(0, ANGLE_SCALE_BITS)
		_angle_scale = bytes.decode_double(0)
	return _angle_scale

## x87 FISTP under round-to-nearest-even; out of int32 range gives the integer indefinite 0x80000000.
static func fistp(v: float) -> int:
	if is_nan(v):
		return INT32_MIN
	var f: float = floor(v)
	var d: float = v - f
	if d > 0.5 or (d == 0.5 and fmod(f, 2.0) != 0.0):
		f += 1.0
	if f < -2147483648.0 or f > 2147483647.0:
		return INT32_MIN
	return int(f)

## 0x4b7173: a' = a*cos - b*sin, b' = a*sin + b*cos with theta = s16(angle) * [0x509ef8], x87 at 53-bit precision.
## A zero angle returns the pair untouched (no rounding).
static func rotate_pair(a: int, b: int, angle: int) -> Array:
	var word := s16(angle)
	if word == 0:
		return [a, b]
	var theta := float(word) * angle_scale()
	var c: float = cos(theta)
	var s: float = sin(theta)
	var fa := float(a)
	var fb := float(b)
	return [fistp(fa * c - fb * s), fistp(fb * c + fa * s)]

## 0x4b6cc0(in, out, angles): (x,y) by angles[0] (+0x64), (y,z) by angles[2] (+0x68), (x,z) by angles[1] (+0x66).
static func rotate(point: Array, angles: Array) -> Array:
	var xy := rotate_pair(int(point[0]), int(point[1]), int(angles[0]))
	var yz := rotate_pair(int(xy[1]), int(point[2]), int(angles[2]))
	var xz := rotate_pair(int(xy[0]), int(yz[1]), int(angles[1]))
	return [xz[0], yz[0], xz[1]]

## 0x4cb650(model, min, max, 0): box starts at (0,0,0); the root piece's own vertices (plus its offset, int32 wrap)
## extend it only when the signed vertex count is > 2. Children/siblings are not visited (flag 0).
static func root_bbox(vertices: Array, piece_offset: Array, vertex_count: int = -2147483648) -> Array:
	var count := vertices.size() if vertex_count == INT32_MIN else vertex_count
	var lo := [0, 0, 0]
	var hi := [0, 0, 0]
	if count > 2:
		for i in count:
			var v: Array = vertices[i]
			for axis in 3:
				var value := s32(int(v[axis]) + int(piece_offset[axis]))
				if value > hi[axis]:
					hi[axis] = value
				if value < lo[axis]:
					lo[axis] = value
	return [lo, hi]

## Root model record from a prepared 3DO piece (tools/prepare_viewer.py model_3do: raw file values, pieces[0] is the
## root). Applies the loader's 0x4cb590 conversion: vertex x/z and piece offset x/z negated, y kept.
static func model_from_3do_piece(piece: Dictionary) -> Dictionary:
	var vertices := []
	for v in piece.vertices:
		vertices.append([s32(-int(v[0])), int(v[1]), s32(-int(v[2]))])
	var offset: Array = piece.offset
	return {"count": vertices.size(), "offset": [s32(-int(offset[0])), int(offset[1]), s32(-int(offset[2]))], "vertices": vertices}

static func model_bbox(model: Dictionary) -> Array:
	return root_bbox(model.vertices, model.offset, int(model.count))

## 0x48c6a0 projection: corners (min.x,min.z) (max.x,min.z) (max.x,max.z) (min.x,max.z) at y = min.y, rotated,
## then sx = s16((r.x + (u.x - (camX<<16))) >> 16) + 128 and
## sy = s16(((u.z - (camY<<16)) - r.z) >> 16) - (s16((r.y + u.y) >> 16) >> 1) + 32. The +128/+32 are constants,
## not the view rect fields.
static func project_corners(unit: Dictionary, bbox: Array, cam: Dictionary) -> Array:
	var lo: Array = bbox[0]
	var hi: Array = bbox[1]
	var corners := [[lo[0], lo[1], lo[2]], [hi[0], lo[1], lo[2]], [hi[0], lo[1], hi[2]], [lo[0], lo[1], hi[2]]]
	var bx := s32(int(unit.x) - s32(int(cam.x) * 65536))
	var bz := s32(int(unit.z) - s32(int(cam.y) * 65536))
	var out := []
	for corner in corners:
		var r := rotate(corner, unit.angles)
		var sx := s16(s32(int(r[0]) + bx) >> 16) + 0x80
		var ey := s16(s32(int(r[1]) + int(unit.y)) >> 16)
		var sy := s16(s32(bz - int(r[2])) >> 16) - (ey >> 1) + 0x20
		out.append([sx, sy])
	return out

## 0x4c1320(points, n, px, py): n < 3 is outside; every edge i -> (i+1)%n needs
## (yj-yi)*(px-xi) > (xj-xi)*(py-yi) in int32 wraparound, so boundary points are outside.
static func inside(corners: Array, px: int, py: int) -> bool:
	var n := corners.size()
	if n < 3:
		return false
	for i in n:
		var p: Array = corners[i]
		var q: Array = corners[(i + 1) % n]
		var lhs := s32(s32(int(q[1]) - int(p[1])) * s32(px - int(p[0])))
		var rhs := s32(s32(int(q[0]) - int(p[0])) * s32(py - int(p[1])))
		if lhs <= rhs:
			return false
	return true

## 0x48ce1e: key = low32(((int64)low32(((int64)size.y * 0x8000) >> 16) + size.z) * size.x >> 16), signed.
## (size.y/2 + size.z) * size.x in 16.16: the drawn footprint area. Smaller keys win.
static func key(def: Dictionary) -> int:
	var size: Array = def.size
	var half_height := s32((int(size[1]) * 0x8000) >> 16)
	var depth := s32(half_height + int(size[2]))
	return s32((depth * int(size[0])) >> 16)

static func in_rect(rect: Dictionary, x: int, y: int) -> bool:
	return x >= int(rect.left) and x <= int(rect.right) and y >= int(rect.top) and y <= int(rect.bottom)

static func _def(unit: Dictionary, defs: Array) -> Dictionary:
	if unit.has("def"):
		return unit.def
	return defs[int(unit.def_index)]

static func _model(models: Dictionary, type_id: int) -> Dictionary:
	if models.has(type_id):
		return models[type_id]
	return models[str(type_id)]

## 0x48c6a0 for one unit: true when the mouse is strictly inside the projected rotated root bbox.
static func hit(unit: Dictionary, model: Dictionary, cam: Dictionary, mouse: Vector2i) -> bool:
	return inside(project_corners(unit, model_bbox(model), cam), mouse.x, mouse.y)

## Main view branch of 0x48cd80. list = visible list entries (unit slot numbers, words) or null for the NULL list
## pointer. Returns the +0xa8 index word of the smallest-key hit (strict <, so the earliest list entry wins ties and
## keys >= 0x7fff0000 never win), or 0. Mouse outside the view rect returns 0 here (see hover()).
static func pick(list, units: Array, defs: Array, models: Dictionary, cam: Dictionary, view: Dictionary, mouse: Vector2i) -> int:
	if not in_rect(view, mouse.x, mouse.y) or list == null:
		return 0
	var best := NO_KEY
	var result := 0
	for entry in list:
		var unit: Dictionary = units[int(entry) & 0xFFFF]
		if (int(unit.type_id) & 0xFFFF) == 0:
			continue
		if not hit(unit, _model(models, int(unit.type_id) & 0xFFFF), cam, mouse):
			continue
		var k := key(_def(unit, defs))
		if k < best:
			best = k
			result = int(unit.index) & 0xFFFF
	return result

## Minimap branch of 0x48cd80: d2 = (bx-mx)^2 + (by-my)^2 in int32 wraparound; keep d2 < 4 and d2 < best (best
## starts at 99999, strict so the first blip wins ties). A wrapped negative d2 also qualifies, as in the original.
static func minimap_pick(blips: Array, mouse: Vector2i) -> int:
	var best := 99999
	var result := 0
	for blip in blips:
		var dx := s32(int(blip[1]) - mouse.x)
		var dy := s32(int(blip[2]) - mouse.y)
		var d2 := s32(s32(dx * dx) + s32(dy * dy))
		if d2 < 4 and d2 < best:
			best = d2
			result = int(blip[0]) & 0xFFFF
	return result

## Full 0x48cd80: view rect first (raw mouse), else minimap rect (game +0x142bb), else 0.
static func hover(mouse: Vector2i, view: Dictionary, list, units: Array, defs: Array, models: Dictionary, cam: Dictionary, minimap_rect: Dictionary, blips: Array) -> int:
	if in_rect(view, mouse.x, mouse.y):
		return pick(list, units, defs, models, cam, view, mouse)
	if in_rect(minimap_rect, mouse.x, mouse.y):
		return minimap_pick(blips, mouse)
	return 0

## 0x48bae0 visible list, in slot order. visible_fn(slot: int, unit: Dictionary) -> bool stands for
## 0x465ac0(player G+0x1b63 + local*0x14b, unit) and is called only for kept units whose owner byte differs from
## local_player. Integer parts are the signed high words of the 16.16 fields.
static func visible_list(units: Array, defs: Array, cells: Dictionary, cam: Dictionary, view: Dictionary, local_player: int, visible_fn: Callable) -> Array:
	var out := []
	var cam_x := int(cam.x)
	var cam_y := int(cam.y)
	for slot in units.size():
		var unit: Dictionary = units[slot]
		if (int(unit.type_id) & 0xFFFF) == 0:
			continue
		var def := _def(unit, defs)
		var lo: Array = def.min
		var hi: Array = def.max
		var xi := s16(int(unit.x) >> 16)
		var yi := s16(int(unit.y) >> 16)
		var zi := s16(int(unit.z) >> 16)
		var left := s32(s16(int(lo[0]) >> 16) + xi - cam_x)
		var top_y := s16(int(hi[1]) >> 16) + yi
		var top_z := s32(s16(int(lo[2]) >> 16) + zi - cam_y)
		var right := s32(s16(int(hi[0]) >> 16) + xi - cam_x)
		var bottom_y := s16(int(lo[1]) >> 16) + yi
		var bottom_z := s32(s16(int(hi[2]) >> 16) + zi - cam_y)
		if (int(unit.flags110) & 3) != 1:
			var h := cell_height(cells, int(unit.x), int(unit.z))
			if h >= 0 and bottom_y > h:
				bottom_y = h
		left = s32(left + 0x80)
		right = s32(right + 0x80)
		var top := s32(top_z - (top_y >> 1) + 0x20)
		var bottom := s32(bottom_z - (bottom_y >> 1) + 0x20)
		if left > int(view.right) or right < int(view.left) or top > int(view.bottom) or bottom < int(view.top):
			continue
		if (int(unit.owner) & 0xFF) != (local_player & 0xFF) and not visible_fn.call(slot, unit):
			continue
		out.append(int(unit.index) & 0xFFFF)
	return out

## 0x4815a0: cell (x sar 20, z sar 20) with signed bounds against cells w/h; returns the height byte or -1.
static func cell_height(cells: Dictionary, x: int, z: int) -> int:
	var cx := s32(x) >> 20
	var cz := s32(z) >> 20
	if cx < 0 or cx >= int(cells.w) or cz < 0 or cz >= int(cells.h):
		return -1
	return int(cells.heights[cz * int(cells.w) + cx]) & 0xFF

## 0x466dc0 blip list (unit loop). Shown when (flags14281 & 3) == 0, or flags37f2f bit 9, or unit flags110 & 0x300,
## or owner byte == local_player. mm = {"x0","y0","w","h"} words (game +0x142e7/+0x142e9/+0x142eb/+0x142ed);
## scroll_w/scroll_h = game +0x1422b/+0x1422f (C truncating division).
static func minimap_blips(units: Array, local_player: int, flags14281: int, flags37f2f: int, mm: Dictionary, scroll_w: int, scroll_h: int) -> Array:
	var all := (flags14281 & 3) == 0 or ((flags37f2f >> 9) & 1) != 0
	var out := []
	for unit in units:
		if (int(unit.type_id) & 0xFFFF) == 0:
			continue
		if not all and (int(unit.flags110) & 0x300) == 0 and (int(unit.owner) & 0xFF) != (local_player & 0xFF):
			continue
		var bx := s32(s16(int(unit.x) >> 16) * s16(int(mm.w))) / scroll_w
		var yi := s16(int(unit.y) >> 16) >> 1
		var by := s32((s16(int(unit.z) >> 16) - yi) * s16(int(mm.h))) / scroll_h
		out.append([int(unit.index) & 0xFFFF, s32(s16(int(mm.x0)) + bx), s32(s16(int(mm.y0)) + by)])
	return out
