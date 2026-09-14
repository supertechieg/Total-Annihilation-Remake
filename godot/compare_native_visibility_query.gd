extends SceneTree
const VisibilityQueries = preload("res://visibility_queries.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/visibility/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-visibility-query.json")))
	var checks := 0
	var mismatches := 0
	var differences := []
	var modes := {}
	for scene: Dictionary in trace.scenes:
		var world := {"flags": int(scene.flags), "mapped": Marshalls.base64_to_raw(scene.mapped),
			"local_player": int(scene.local_player), "sea_level": int(scene.sea_level)}
		var recs := []
		for rec: Dictionary in scene.recs:
			recs.append({"index": int(rec.index), "w2": int(scene.w2), "h2": int(scene.h2), "los": Marshalls.base64_to_raw(rec.los)})
		var mode: String = scene.mode
		if not modes.has(mode):
			modes[mode] = {"calls": 0, "mismatches": 0, "true": 0, "own_bit_would_differ": 0}
		var stats: Dictionary = modes[mode]
		# Discrimination: the same call answered with the record's own mapped bit instead of the local player's.
		var own_world := world.duplicate()
		for row: Array in scene.calls:
			var expected := int(row[row.size() - 1]) != 0
			var actual := false
			var own := false
			var rec: Dictionary = recs[int(row[0])]
			own_world.local_player = int(rec.index)
			var text := ""
			match String(scene.kind):
				"visible":
					var unit := {"owner": int(row[1]), "state10e": int(row[2]), "vis_flags": int(row[3]),
						"pos16": [int(row[4]), int(row[5]), int(row[6])],
						"bounds": [int(row[7]), int(row[8]), int(row[9]), int(row[10]), int(row[11]), int(row[12])]}
					actual = VisibilityQueries.visible(rec, world, unit)
					own = VisibilityQueries.visible(rec, own_world, unit)
					text = "visible %s" % [row]
				"feature":
					actual = VisibilityQueries.feature_visible(rec, world, int(row[1]), int(row[2]), int(row[3]), int(row[4]), int(row[5]))
					own = VisibilityQueries.feature_visible(rec, own_world, int(row[1]), int(row[2]), int(row[3]), int(row[4]), int(row[5]))
					text = "feature %s" % [row]
				"probe":
					actual = VisibilityQueries.mapped_probe(rec, world, [int(row[1]), int(row[2]), int(row[3])])
					own = VisibilityQueries.mapped_probe(rec, own_world, [int(row[1]), int(row[2]), int(row[3])])
					text = "probe %s" % [row]
			checks += 1
			stats.calls += 1
			if expected:
				stats["true"] += 1
			if own != expected:
				stats.own_bit_would_differ += 1
			if actual != expected:
				mismatches += 1
				stats.mismatches += 1
				if differences.size() < 20:
					differences.append({"mode": mode, "w2": scene.w2, "h2": scene.h2, "flags": scene.flags, "local_player": scene.local_player,
						"sea_level": scene.sea_level, "call": text, "native": expected, "port": actual})
	var report := {"exe_sha256": trace.exe_sha256, "routines": trace.routines, "checks": checks, "mismatches": mismatches,
		"modes": modes, "differences": differences,
		"scope": "Every native 0x465ac0 / 0x4658e0 / 0x408090 result on random LOS byte grids, mapped words, flags, local player (incl. >=16 shift), sea level, unit bounds and positions (map edges, negative, 16-bit wrap) reproduced by godot/visibility_queries.gd; own_bit_would_differ counts calls whose answer changes if the record's own mapped bit were used instead of the local player's (shows the quirk is exercised)"}
	var out := ProjectSettings.globalize_path("res://../analysis/native-visibility-query-validation.json")
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true))
	for mode: String in modes:
		print("MODE %s %s" % [mode, modes[mode]])
	print("VISIBILITY_QUERY_NATIVE %d / %d checks match" % [checks - mismatches, checks])
	quit(0 if mismatches == 0 else 1)
