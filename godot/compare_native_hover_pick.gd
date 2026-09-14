extends SceneTree
## Compare hover_pick.gd with the original 0x48cd80 / 0x48c6a0 / 0x4cb650 / 0x4b6cc0 / 0x48bae0 / 0x466dc0 run by
## tools/native_hover_pick.py.
const HoverPick = preload("res://hover_pick.gd")

var checks := 0
var failures := 0

func expect(label: String, expected, actual) -> void:
	checks += 1
	if not _same(expected, actual):
		failures += 1
		if failures <= 12:
			printerr("%s: expected %s got %s" % [label, expected, actual])

func _same(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return int(a) == int(b)
	return a == b

static func ints(value):
	if value is Array:
		return value.map(func(v): return ints(v))
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = ints(value[k])
		return out
	if value is float:
		return int(value)
	return value

func _initialize() -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../local/cursor/native-hover-pick.json"))
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		printerr("Run tools/native_hover_pick.py first")
		quit(1)
		return
	for case in data.rotations:
		expect("rotate %s %s" % [case[0], case[1]], case[2], HoverPick.rotate(ints(case[0]), ints(case[1])))
	for scene_index in data.picks.size():
		var scene: Dictionary = ints(data.picks[scene_index])
		var units: Array = scene.units
		for type_id in scene.bboxes:
			expect("bbox scene %d type %s" % [scene_index, type_id], scene.bboxes[type_id], HoverPick.model_bbox(scene.models[type_id]))
		for pair in scene.keys:
			expect("key scene %d slot %d" % [scene_index, pair[0]], pair[1], HoverPick.key(scene.defs[int(units[pair[0]].def_index)]))
		expect("null list scene %d" % scene_index, scene.null_list_result, HoverPick.pick(null, units, scene.defs, scene.models, scene.cam, scene.view, Vector2i(scene.calls[0].mouse[0], scene.calls[0].mouse[1])))
		for call in scene.calls:
			var mouse := Vector2i(call.mouse[0], call.mouse[1])
			for h in call.hits:
				var unit: Dictionary = units[h[0]]
				var model: Dictionary = scene.models[str(unit.type_id)]
				var corners := HoverPick.project_corners(unit, HoverPick.model_bbox(model), scene.cam)
				expect("corners scene %d slot %d" % [scene_index, h[0]], h[2], corners)
				expect("inside scene %d slot %d mouse %s" % [scene_index, h[0], mouse], h[1] != 0, HoverPick.inside(corners, mouse.x, mouse.y))
			expect("pick scene %d mouse %s" % [scene_index, mouse], call.result, HoverPick.pick(scene.list, units, scene.defs, scene.models, scene.cam, scene.view, mouse))
	for scene_index in data.minimaps.size():
		var scene: Dictionary = ints(data.minimaps[scene_index])
		var blips: Array = scene.blips if int(scene.count) > 0 else []
		for call in scene.calls:
			var mouse := Vector2i(call.mouse[0], call.mouse[1])
			expect("minimap scene %d mouse %s" % [scene_index, mouse], call.result, HoverPick.hover(mouse, scene.view, [], [], [], {}, {"x": 0, "y": 0}, scene.rect, blips))
	for scene_index in data.visibles.size():
		var scene: Dictionary = ints(data.visibles[scene_index])
		var cells := {"w": scene.cells_w, "h": scene.cells_h, "heights": PackedByteArray(scene.heights)}
		var calls := []
		var answers: Array = scene.visible_answers
		var fn := func(slot: int, _unit: Dictionary) -> bool:
			calls.append(slot)
			return bool(answers[slot])
		var list := HoverPick.visible_list(scene.units, scene.defs, cells, scene.cam, scene.view, scene.local_player, fn)
		expect("visible list scene %d" % scene_index, scene.list, list)
		expect("visible calls scene %d" % scene_index, scene.visible_calls, calls)
	for scene_index in data.blips.size():
		var scene: Dictionary = ints(data.blips[scene_index])
		var blips := HoverPick.minimap_blips(scene.units, scene.local_player, scene.flags14281, scene.flags37f2f, scene.minimap, scene.scroll_w, scene.scroll_h)
		expect("blips scene %d" % scene_index, scene.blips, blips)
	print("HOVER_PICK_NATIVE %d / %d checks match" % [checks - failures, checks])
	quit(0 if failures == 0 and checks > 0 else 1)
