extends SceneTree
## Hand-computed fixtures for hover_pick.gd (the native oracle comparison is compare_native_hover_pick.gd).
const HoverPick = preload("res://hover_pick.gd")

var checks := 0
var failures := 0

func expect(label: String, expected, actual) -> void:
	checks += 1
	if typeof(expected) != typeof(actual) or expected != actual:
		failures += 1
		printerr("%s: expected %s got %s" % [label, expected, actual])

func box_model(half: int, height: int) -> Dictionary:
	# Root piece with 4 vertices spanning x/z in [-half, half] (16.16) and y in [0, height].
	return {"count": 4, "offset": [0, 0, 0], "vertices": [[-half, 0, -half], [half, height, -half], [half, 0, half], [-half, 0, half]]}

func unit_at(x: int, z: int, index: int, def_index := 0) -> Dictionary:
	return {"type_id": 1, "index": index, "x": x << 16, "y": 0, "z": z << 16, "angles": [0, 0, 0], "owner": 0, "flags110": 0, "def_index": def_index}

func _initialize() -> void:
	# Root bbox: starts at the origin, needs more than 2 vertices, adds the piece offset.
	expect("bbox two vertices", [[0, 0, 0], [0, 0, 0]], HoverPick.root_bbox([[5, 6, 7], [-5, -6, -7]], [0, 0, 0]))
	expect("bbox three vertices", [[-5, 0, -7], [10, 6, 0]], HoverPick.root_bbox([[5, 6, -7], [-5, 2, -1], [10, 1, -3]], [0, 0, 0]))
	expect("bbox offset", [[0, 0, 0], [15, 106, 9]], HoverPick.root_bbox([[5, 6, -7], [-5, 2, -1], [10, 1, -3]], [5, 100, 10]))
	expect("bbox count field", [[0, 0, 0], [0, 0, 0]], HoverPick.root_bbox([[5, 6, -7], [-5, 2, -1], [10, 1, -3]], [0, 0, 0], 2))
	var converted := HoverPick.model_from_3do_piece({"offset": [1, 2, 3], "vertices": [[4, 5, 6], [-7, 8, -9]]})
	expect("3do axis conversion", {"count": 2, "offset": [-1, 2, -3], "vertices": [[-4, 5, -6], [7, 8, 9]]}, converted)
	# FISTP rounding.
	expect("fistp 2.5", 2, HoverPick.fistp(2.5))
	expect("fistp 3.5", 4, HoverPick.fistp(3.5))
	expect("fistp -2.5", -2, HoverPick.fistp(-2.5))
	expect("fistp overflow", -2147483648, HoverPick.fistp(2147483648.0))
	# Rotation: zero is untouched, quarter turns, and the (x,y) -> (y,z) -> (x,z) order.
	expect("rotate zero", [123456789, -5, 2147483647], HoverPick.rotate([123456789, -5, 2147483647], [0, 0, 0]))
	expect("rotate roll quarter", [0, 65536, 0], HoverPick.rotate([65536, 0, 0], [0x4000, 0, 0]))
	expect("rotate roll then pitch", [0, 0, 65536], HoverPick.rotate([65536, 0, 0], [0x4000, 0, 0x4000]))
	expect("rotate heading", [0, 0, 65536], HoverPick.rotate([65536, 0, 0], [0, 0x4000, 0]))
	expect("rotate half turn", [-65536, 0, 0], HoverPick.rotate([65536, 0, 0], [0x8000, 0, 0]))
	# Projection: model z is subtracted, +128/+32 constants, height halves upward.
	var unit := unit_at(200, 100, 7)
	var bbox := HoverPick.model_bbox(box_model(8 << 16, 10 << 16))
	var corners := HoverPick.project_corners(unit, bbox, {"x": 0, "y": 0})
	expect("corners", [[320, 140], [336, 140], [336, 124], [320, 124]], corners)
	expect("inside centre", true, HoverPick.inside(corners, 328, 132))
	expect("edge left outside", false, HoverPick.inside(corners, 320, 132))
	expect("edge bottom outside", false, HoverPick.inside(corners, 328, 140))
	expect("just inside", true, HoverPick.inside(corners, 321, 139))
	var raised: Dictionary = unit.duplicate()
	raised.y = 20 << 16
	expect("height lifts", [[320, 130], [336, 130], [336, 114], [320, 114]], HoverPick.project_corners(raised, bbox, {"x": 0, "y": 0}))
	expect("camera", [[310, 135], [326, 135], [326, 119], [310, 119]], HoverPick.project_corners(unit, bbox, {"x": 10, "y": 5}))
	expect("fewer than three corners", false, HoverPick.inside([[0, 0], [10, 10]], 5, 5))
	# Key = (size.y/2 + size.z) * size.x in 16.16.
	var small := {"min": [0, 0, 0], "max": [0, 0, 0], "size": [2 << 20, 10 << 16, 2 << 20]}
	var large := {"min": [0, 0, 0], "max": [0, 0, 0], "size": [4 << 20, 10 << 16, 4 << 20]}
	var limit := {"min": [0, 0, 0], "max": [0, 0, 0], "size": [0x10000, 0, 0x7fff0000]}
	expect("key", 1184 << 16, HoverPick.key(small))
	expect("key limit", 0x7fff0000, HoverPick.key(limit))
	# Pick: smallest key, earlier entry on ties, 0x7fff0000 never wins, empty slots skipped, view gate, NULL list.
	var models := {1: box_model(8 << 16, 10 << 16)}
	var view := {"left": 128, "top": 32, "right": 639, "bottom": 447}
	var cam := {"x": 0, "y": 0}
	var units := [unit_at(200, 100, 11, 1), unit_at(200, 100, 12, 0), unit_at(200, 100, 13, 0), unit_at(200, 100, 14, 2)]
	var defs := [small, large, limit]
	var mouse := Vector2i(328, 132)
	expect("pick smallest key", 12, HoverPick.pick([0, 1, 2], units, defs, models, cam, view, mouse))
	expect("pick tie earlier", 13, HoverPick.pick([0, 2, 1], units, defs, models, cam, view, mouse))
	expect("pick key limit", 0, HoverPick.pick([3], units, defs, models, cam, view, mouse))
	expect("pick miss", 0, HoverPick.pick([0, 1], units, defs, models, cam, view, Vector2i(400, 300)))
	expect("pick null list", 0, HoverPick.pick(null, units, defs, models, cam, view, mouse))
	var empty: Array = units.duplicate(true)
	empty[1].type_id = 0
	expect("pick empty slot", 13, HoverPick.pick([1, 2], empty, defs, models, cam, view, mouse))
	expect("pick outside view", 0, HoverPick.pick([1], units, defs, models, cam, {"left": 330, "top": 32, "right": 639, "bottom": 447}, mouse))
	# Minimap blips: d2 < 4, first wins ties, int32-wrapped distances qualify.
	expect("blip near", 5, HoverPick.minimap_pick([[4, 20, 20], [5, 11, 11]], Vector2i(10, 10)))
	expect("blip d2 4 rejected", 0, HoverPick.minimap_pick([[4, 12, 10]], Vector2i(10, 10)))
	expect("blip tie first", 4, HoverPick.minimap_pick([[4, 9, 10], [5, 11, 10]], Vector2i(10, 10)))
	expect("blip wrapped", 6, HoverPick.minimap_pick([[6, 10 + 46341, 10]], Vector2i(10, 10)))
	var minimap_rect := {"left": 0, "top": 0, "right": 120, "bottom": 120}
	expect("hover view", 12, HoverPick.hover(mouse, view, [0, 1], units, defs, models, cam, minimap_rect, [[9, 328, 132]]))
	expect("hover minimap", 9, HoverPick.hover(Vector2i(50, 60), view, [0, 1], units, defs, models, cam, minimap_rect, [[9, 50, 61]]))
	expect("hover nowhere", 0, HoverPick.hover(Vector2i(125, 20), view, [0, 1], units, defs, models, cam, minimap_rect, [[9, 125, 20]]))
	# Visible list: bbox overlap with the inclusive view rect, owner or visible_fn, cell lowering unless flags & 3 == 1.
	var vdef := {"min": [-(8 << 16), 0, -(8 << 16)], "max": [8 << 16, 20 << 16, 8 << 16], "size": [0, 0, 0]}
	var cells := {"w": 4, "h": 4, "heights": PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])}
	var calls := []
	var fn := func(slot: int, _u: Dictionary) -> bool:
		calls.append(slot)
		return slot == 2
	var vunits := [
		{"type_id": 1, "index": 1, "x": 519 << 16, "y": 0, "z": 100 << 16, "owner": 3, "flags110": 0, "def_index": 0},   # left = 639
		{"type_id": 1, "index": 2, "x": 520 << 16, "y": 0, "z": 100 << 16, "owner": 3, "flags110": 0, "def_index": 0},   # left = 640, off view
		{"type_id": 1, "index": 3, "x": 200 << 16, "y": 0, "z": 100 << 16, "owner": 4, "flags110": 0, "def_index": 0},   # enemy, visible
		{"type_id": 1, "index": 4, "x": 200 << 16, "y": 0, "z": 100 << 16, "owner": 5, "flags110": 0, "def_index": 0},   # enemy, hidden
		{"type_id": 0, "index": 5, "x": 200 << 16, "y": 0, "z": 100 << 16, "owner": 3, "flags110": 0, "def_index": 0},
		# bottom = 8 + z - (y>>1) + 32: y 100 on a height-0 cell is lowered to 0 -> bottom = 40 + z; flags&3==1 keeps 50.
		{"type_id": 1, "index": 6, "x": 20 << 16, "y": 100 << 16, "z": -(9 << 16), "owner": 3, "flags110": 0, "def_index": 0},
		{"type_id": 1, "index": 7, "x": 20 << 16, "y": 100 << 16, "z": 20 << 16, "owner": 3, "flags110": 1, "def_index": 0},
	]
	# Unit 7 (z 20, not lowered): bottom = 8 + 20 - 50 + 32 = 10 < 32 -> off. Unit 6 at z -9 is off-grid (cz = -1): not
	# lowered either, bottom = 8 - 9 - 50 + 32 < 32 -> off.
	expect("visible list", [1, 3], HoverPick.visible_list(vunits, [vdef], cells, cam, view, 3, fn))
	expect("visible_fn only for other owners", [2, 3], calls)
	var lowered: Dictionary = vunits[6].duplicate()
	lowered.flags110 = 0
	calls.clear()
	expect("cell lowering keeps unit", [7], HoverPick.visible_list([lowered], [vdef], cells, cam, view, 3, fn))
	# Blip list filter and position.
	var bunits := [
		{"type_id": 1, "index": 1, "x": 1000 << 16, "y": 40 << 16, "z": 500 << 16, "owner": 2, "flags110": 0},
		{"type_id": 1, "index": 2, "x": 1000 << 16, "y": 40 << 16, "z": 500 << 16, "owner": 3, "flags110": 0x200},
		{"type_id": 1, "index": 3, "x": 1000 << 16, "y": 40 << 16, "z": 500 << 16, "owner": 3, "flags110": 0},
	]
	var mm := {"x0": 5, "y0": 7, "w": 100, "h": 80}
	expect("blips filtered", [[1, 5 + 1000 * 100 / 2000, 7 + 480 * 80 / 1600], [2, 55, 31]], HoverPick.minimap_blips(bunits, 2, 1, 0, mm, 2000, 1600))
	expect("blips all", 3, HoverPick.minimap_blips(bunits, 2, 0, 0, mm, 2000, 1600).size())
	expect("blips bit 9", 3, HoverPick.minimap_blips(bunits, 2, 1, 0x200, mm, 2000, 1600).size())
	print("HOVER_PICK %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
