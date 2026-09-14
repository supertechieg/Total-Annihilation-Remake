extends SceneTree
## Replays every sequence recorded by tools/native_los_stamp.py (oracle O3) through VisibilityWorld and compares the
## state after every step: every player's padded LOS grid, the mapped word buffer, unit +0x7a/+0x7c/+0xf8, the temp LOS
## count and all 20 backing entries, the flags word, the redraw bit and the minimap stub calls; plus native faults.
const VisibilityWorld = preload("res://visibility_world.gd")
const LosTables = preload("res://los_tables.gd")
const LosHeightGrid = preload("res://los_height_grid.gd")

var checks := 0
var matching := 0
var differences := []
var map_cache := {}


func _h16(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode().substr(0, 16)


func _map_heights(key: String) -> Dictionary:
	if not map_cache.has(key):
		var folder := ProjectSettings.globalize_path("res://../local/maps/").path_join(key)
		var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("scene.json")))
		map_cache[key] = {"w": int(scene.height_grid_width), "h": int(scene.height_grid_height),
			"heights": FileAccess.get_file_as_bytes(folder.path_join("heights.bin"))}
	return map_cache[key]


func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/visibility/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-los-stamp.json")))
	var tdf_bytes := FileAccess.get_file_as_bytes(folder.path_join("los.tdf"))
	var chars := PackedStringArray()
	for b in tdf_bytes:
		chars.append(String.chr(b))
	var tables: Array = LosTables.parse("".join(chars))
	var frames: Array = VisibilityWorld.frames_from_json(JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("vismasks.json"))))
	var table_text := PackedStringArray()
	for table: Array in tables:
		var rays := PackedStringArray()
		for ray: PackedInt32Array in table:
			var steps := PackedStringArray()
			for i in range(ray.size() >> 1):
				steps.append("%d,%d" % [ray[i * 2], ray[i * 2 + 1]])
			rays.append(" ".join(steps))
		table_text.append("|".join(rays))
	_check(_h16("#".join(table_text).to_utf8_buffer()) == trace.tables_sha and frames.size() == int(trace.frame_count),
		{"what": "ray tables / vismask frames differ from the native structures"})
	var faults := 0
	var steps_total := 0
	for sequence: Dictionary in trace.sequences:
		var scene: Dictionary = sequence.scene
		var src := _map_heights(scene.map)
		var crop: Array = scene.crop
		var width := int(scene.width)
		var height := int(scene.height)
		var heights := PackedByteArray()
		heights.resize(width * height)
		for r in range(height):
			for c in range(width):
				heights[r * width + c] = src.heights[(int(crop[1]) + r) * int(src.w) + int(crop[0]) + c]
		var hg: Dictionary = LosHeightGrid.build(heights, width, height, int(scene.sea_level))
		var native_hg: Dictionary = scene.height_grid
		if not _check(_h16(hg.grid) == native_hg.sha and int(hg.w2) == int(native_hg.w2) and int(hg.h2) == int(native_hg.h2),
				{"sequence": sequence.index, "what": "height grid differs from native 0x482c20"}):
			continue
		var world = VisibilityWorld.new()
		world.setup(width, height, int(scene.sea_level), hg, tables, frames)
		for p: Dictionary in scene.players:
			world.add_player(int(p.slot), int(p.index), int(p.type))
		world.local_player = int(scene.local)
		world.flags = int(scene.flags)
		world.tick = int(scene.tick)
		match String(scene.initial_mapped_kind):
			"ones":
				var ones := PackedByteArray()
				ones.resize(world.mapped.size())
				ones.fill(0xFF)
				world.mapped = ones
			"random":
				world.mapped = Marshalls.base64_to_raw(scene.initial_mapped)
		var units := {}
		var alive := {}
		for i in range(1, int(scene.unit_slots) + 1):
			units[i] = {"owner": 0, "pos16": [0, 0, 0], "sight": 0, "eye_bonus": 0, "unit_flags": 0, "los_col": 0, "los_row": 0, "los_slot": 0}
		var ops: Array = sequence.ops
		var states: Array = sequence.states
		for step in range(ops.size()):
			var op: Dictionary = ops[step]
			if op.get("overlay", false):
				world.flags |= 8
			world.redraw_dirty = false
			match String(op.op):
				"create":
					var u: Dictionary = units[int(op.u)]
					u.owner = int(op.owner)
					u.pos16 = _ints(op.pos)
					u.los_col = VisibilityWorld.s16(int(op.origin[0]))
					u.los_row = VisibilityWorld.s16(int(op.origin[1]))
					u.los_slot = int(op.slot) & 0xFF
					u.sight = VisibilityWorld.s16(int(op.sight))
					u.eye_bonus = int(op.eye)
					u.unit_flags = int(op.unit_flags)
					alive[int(op.u)] = true
					world.create_unit(u)
				"move":
					var u: Dictionary = units[int(op.u)]
					u.pos16 = _ints(op.pos)
					world.update_unit(u)
				"death":
					world.kill_unit(units[int(op.u)])
					alive.erase(int(op.u))
				"temp":
					world.add_temp_los(_ints(op.pos), int(op.sight), int(op.eye), int(op.duration))
				"tick":
					world.tick = (world.tick + int(op.n)) & 0xFFFFFFFF
					world.expire_temp_los()
				"rebuild":
					var list := []
					for i in range(1, int(scene.unit_slots) + 1):
						if alive.has(i):
							list.append(units[i])
					world.rebuild(int(op.reset) != 0, list)
				"flags":
					world.flags = int(op.value)
			var expected: Dictionary = states[step]
			steps_total += 1
			var where := {"sequence": sequence.index, "step": step, "op": op}
			if expected.has("fault"):
				faults += 1
				_check(world.fault != null, where.merged({"what": "native fault not reproduced", "native": expected.fault}))
				break
			if not _check(world.fault == null, where.merged({"what": "port fault without native fault", "port": world.fault})):
				break
			var actual := _state(world, scene, units)
			var bad := []
			for key in ["los", "mapped", "units", "temp_count", "temp", "flags", "dirty", "minimap"]:
				if JSON.stringify(_norm(actual[key])) != JSON.stringify(_norm(expected[key])):
					bad.append({"field": key, "port": actual[key], "native": expected[key]})
			if not _check(bad.is_empty(), where.merged({"what": "state", "fields": bad})):
				break
	var report := {"exe_sha256": trace.exe_sha256, "checks": checks, "matching": matching, "sequences": trace.sequences.size(),
		"steps": steps_total, "native_faults": faults, "totals": trace.totals, "native_coverage": trace.coverage, "native_grid_stats": trace.grid_stats, "stubs": trace.stubs, "assumptions": trace.assumptions,
		"differences": differences,
		"scope": "VisibilityWorld create/update/death/temp/expiry/rebuild vs original 0x482ac0/0x4827b0/0x482090/0x482910/0x482130/0x4816a0 (with 0x4825b0/0x482270/0x481d50/0x481930) on real map height grids, the original-loaded ray tables and vismasks.gaf frames; full LOS grids (all players), mapped buffer, unit +0x7a/+0x7c/+0xf8, temp array/count, flags word, 0x142f1 bit, faults, after every step"}
	FileAccess.open(ProjectSettings.globalize_path("res://../analysis/native-los-stamp-validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true))
	for d in differences.slice(0, 5):
		print(JSON.stringify(d))
	print("LOS_STAMP_NATIVE %d / %d checks match" % [matching, checks])
	quit(0 if matching == checks else 1)


func _norm(value):
	if value is float:
		return int(value)
	if value is Array:
		var out := []
		for v in value:
			out.append(_norm(v))
		return out
	return value


func _ints(values: Array) -> Array:
	var out := []
	for v in values:
		out.append(int(v))
	return out


func _state(world, scene: Dictionary, units: Dictionary) -> Dictionary:
	var los := []
	for p: Dictionary in scene.players:
		los.append(_h16(world.players[int(p.slot)].los))
	var unit_rows := []
	for i in range(1, int(scene.unit_slots) + 1):
		var u: Dictionary = units[i]
		unit_rows.append([VisibilityWorld.s16(int(u.los_col)), VisibilityWorld.s16(int(u.los_row)), int(u.los_slot) & 0xFF])
	return {"los": los, "mapped": _h16(world.mapped), "units": unit_rows, "temp_count": world.temp_count,
		"temp": _h16(world.temp_canonical().to_utf8_buffer()), "flags": world.flags, "dirty": 4 if world.redraw_dirty else 0,
		"minimap": [world.minimap_terrain_calls, world.minimap_dots_calls]}


func _check(ok: bool, detail: Dictionary) -> bool:
	checks += 1
	if ok:
		matching += 1
	elif differences.size() < 40:
		differences.append(detail)
	return ok
