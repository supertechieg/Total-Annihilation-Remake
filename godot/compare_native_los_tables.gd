extends SceneTree
const LosTables = preload("res://los_tables.gd")

var checks := {"x": 0, "y": 0}
var differences := []

func _check(ok: bool, label: String, reason: String) -> void:
	checks.y += 1
	if ok:
		checks.x += 1
	elif differences.size() < 40:
		differences.append({"case": label, "reason": reason})

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../local/visibility/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("native-los-tables.json")))
	var tdf_bytes := FileAccess.get_file_as_bytes(folder.path_join("los.tdf"))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(tdf_bytes)
	_check(ctx.finish().hex_encode() == trace.tdf_sha256, "los.tdf", "local/visibility/los.tdf hash differs from the native trace input")
	var rays_compared := 0
	var entries_compared := 0
	var fault_cases := []
	var summary := {}
	for case: Dictionary in trace.cases:
		var label: String = case.name
		var text: String = case.text
		if label == "los.tdf":
			# Decode the extracted file byte-per-codepoint (latin-1), as the oracle did.
			var chars := PackedStringArray()
			for b in tdf_bytes:
				chars.append(String.chr(b))
			_check("".join(chars) == text, label, "trace text differs from local/visibility/los.tdf")
		var actual: Dictionary = LosTables.parse_detailed(text)
		if case.has("fault"):
			fault_cases.append(label)
			var native_fault: Dictionary = case.fault
			# Classify from what the oracle observed, most specific first.
			var expected_kind := "unclassified"
			var located = native_fault.get("last_line_call")
			if native_fault.get("fatal") != null:
				expected_kind = "tdf_parse_error"
			elif native_fault.get("first_out_of_range_ray") != null:
				expected_kind = "ray_index_wrap"
				located = native_fault.first_out_of_range_ray
			elif str(native_fault.eip) == "0x4e4efa":
				expected_kind = "missing_token"
			elif str(native_fault.error).contains("execution limit") or str(native_fault.error).contains("MemoryError"):
				expected_kind = "negative_size"
			_check(actual.fault != null, label, "native faulted (%s at %s) but the port loaded" % [native_fault.error, native_fault.eip])
			if actual.fault != null:
				_check(actual.fault.kind == expected_kind, label, "fault kind %s != native %s" % [actual.fault.kind, expected_kind])
				if expected_kind == "tdf_parse_error":
					_check(str(native_fault.fatal).contains(str(actual.fault.what)), label,
						"parse error '%s' not in native message '%s'" % [actual.fault.what, native_fault.fatal])
				if located != null and int(actual.fault.line) >= 0:
					var where := [int(actual.fault.table), int(actual.fault.line), int(actual.fault.rotation)]
					var native_where := [int(located.table), int(located.line), int(located.rotation)]
					_check(where == native_where, label, "fault at table/line/rotation %s != native %s" % [where, native_where])
			continue  # a fault case has no native tables to compare, whether or not the port faulted
		_check(actual.fault == null, label, "port fault %s but native loaded" % [actual.fault])
		var expected_tables: Array = case.tables
		var tables: Array = actual.tables
		_check(tables.size() == expected_tables.size(), label, "table count %d != native %d" % [tables.size(), expected_tables.size()])
		for i in range(mini(tables.size(), expected_tables.size())):
			var rays: Array = tables[i]
			var expected_rays: Array = expected_tables[i]
			_check(rays.size() == expected_rays.size(), label, "table %d ray count %d != native %d" % [i + 1, rays.size(), expected_rays.size()])
			for r in range(mini(rays.size(), expected_rays.size())):
				var ray: PackedInt32Array = rays[r]
				var expected_ray: Array = expected_rays[r]
				var reason := ""
				if ray.size() != expected_ray.size() * 2:
					reason = "table %d ray %d length %d != native %d" % [i + 1, r, ray.size() / 2, expected_ray.size()]
				else:
					for e in range(expected_ray.size()):
						if ray[e * 2] != int(expected_ray[e][0]) or ray[e * 2 + 1] != int(expected_ray[e][1]):
							reason = "table %d ray %d step %d: (%d,%d) != native (%d,%d)" % [i + 1, r, e, ray[e * 2], ray[e * 2 + 1], expected_ray[e][0], expected_ray[e][1]]
							break
				entries_compared += expected_ray.size()
				rays_compared += 1
				_check(reason == "", label, reason)
		var values: Array = actual.line_values
		var expected_values: Array = case.line_values
		var same_values := values.size() == expected_values.size()
		if same_values:
			for v in range(values.size()):
				if values[v] != expected_values[v]:
					same_values = false
					break
		_check(same_values, label, "line strings %s != native %s" % [str(values).left(200), str(expected_values).left(200)])
		for access: Dictionary in case.accessor:
			var k := int(access.k)
			var got = LosTables.rays_for(tables, k)
			var native_index = access.table_index
			var in_range: bool = native_index != null and int(native_index) >= 0 and int(native_index) < expected_tables.size()
			if in_range:
				_check(got != null and LosTables.table_index(k) == int(native_index), label, "rays_for(%d) index %d != native %d" % [k, LosTables.table_index(k), native_index])
			else:
				_check(got == null and (native_index == null or LosTables.table_index(k) == int(native_index)), label,
					"rays_for(%d) should be outside the vector (native index %s, port %d)" % [k, native_index, LosTables.table_index(k)])
		summary[label] = expected_tables.map(func(t): return t.size())
	var report := {"exe_sha256": trace.exe_sha256, "tdf_sha256": trace.tdf_sha256, "checks": checks.y, "matching": checks.x,
		"cases": trace.cases.size(), "fault_cases": fault_cases, "rays_compared": rays_compared, "ray_steps_compared": entries_compared,
		"rays_per_table": summary, "differences": differences,
		"scope": "LosTables.parse_detailed vs the original loader 0x433130/0x433380/0x4336f0 run natively (TDF parser, strtok, atoi unmodified; file I/O, heap and TLS stubbed) on the extracted gamedata/los.tdf and synthetic variants; every ray step, table/ray counts, the line strings passed to strtok, fault classification and 0x433500 index arithmetic"}
	var out := ProjectSettings.globalize_path("res://../analysis/native-los-tables-validation.json")
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true))
	print("LOS_TABLES_NATIVE %d / %d checks match (%d rays, %d steps, %d cases)" % [checks.x, checks.y, rays_compared, entries_compared, trace.cases.size()])
	for d in differences.slice(0, 10):
		print("  ", d)
	quit(0 if checks.x == checks.y else 1)
