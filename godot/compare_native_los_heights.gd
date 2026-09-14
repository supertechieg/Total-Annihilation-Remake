extends SceneTree
const LosHeightGrid = preload("res://los_height_grid.gd")

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/visibility/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-los-heights.json")))
	var checks := 0
	var mismatches := 0
	var bytes := 0
	var differences := []
	var maps := []
	for case: Dictionary in trace.cases:
		checks += 1
		var heights: PackedByteArray
		if case.kind == "map":
			heights = FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://../local/maps/").path_join(case.map).path_join("heights.bin"))
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_SHA256)
			ctx.update(heights)
			if ctx.finish().hex_encode() != case.heights_sha256:
				mismatches += 1
				differences.append({"label": case.label, "reason": "heights.bin hash differs from the recorded input"})
				continue
			maps.append(case.map)
		else:
			heights = Marshalls.base64_to_raw(case.heights)
		var native: Dictionary = case.native
		var expected := Marshalls.base64_to_raw(native.grid)
		var actual: Dictionary = LosHeightGrid.build(heights, int(case.width), int(case.height), int(case.sea_level))
		var grid: PackedByteArray = actual.grid
		var reason := ""
		if int(actual.w2) != int(native.w2) or int(actual.h2) != int(native.h2) or int(actual.pad) != int(native.pad):
			reason = "size %d,%d,%d != native %d,%d,%d" % [actual.w2, actual.h2, actual.pad, native.w2, native.h2, native.pad]
		elif grid.size() != expected.size():
			reason = "grid bytes %d != native %d" % [grid.size(), expected.size()]
		else:
			bytes += grid.size()
			for i in range(grid.size()):
				if grid[i] != expected[i]:
					reason = "byte %d (entry %d %s): %d != native %d" % [i, i >> 1, "max" if i % 2 == 0 else "min", grid[i], expected[i]]
					break
		if reason != "":
			mismatches += 1
			if differences.size() < 20:
				differences.append({"label": case.label, "width": case.width, "height": case.height, "sea_level": case.sea_level, "reason": reason})
	var report := {"exe_sha256": trace.exe_sha256, "routine": trace.routine, "cases": checks, "mismatches": mismatches,
		"padded_bytes_compared": bytes, "maps": maps, "differences": differences,
		"scope": "LOS height grid {w2,h2,pad} and every padded (max,min) byte from the original 0x482c20 on prepared skirmish maps and random grids; excludes the 8x8 overlay grid built by the same routine"}
	var out := ProjectSettings.globalize_path("res://../analysis/native-los-heights-validation.json")
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true))
	print("LOS_HEIGHTS_NATIVE %d / %d checks match" % [checks - mismatches, checks])
	quit(0 if mismatches == 0 else 1)
