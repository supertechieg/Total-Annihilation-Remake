extends SceneTree
## Replays every tools/native_ai_profile.py case through godot/ai_profile.gd and compares the per-slot weight, weight
## lock, limit and limit lock arrays, the plan flag, the recorded side-effect events, native faults (kind classified by
## the oracle from evidence; "unclassified" never matches) and the 0x409f20 limit tests, then the CRT atof corpus
## (double bits and the x87 float32 narrowing). Prints "AI_PROFILE_NATIVE x / y checks match"; exits 1 on any mismatch.
const AIProfile = preload("res://ai_profile.gd")

var checks := {"x": 0, "y": 0}
var differences := []


func _check(ok: bool, label: String, reason: String) -> void:
	checks.y += 1
	if ok:
		checks.x += 1
	elif differences.size() < 40:
		differences.append("%s: %s" % [label, reason])


func _sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://..")
	var trace_path := root.path_join("local/ai/native-ai-profile.json")
	if not FileAccess.file_exists(trace_path):
		print("AI_PROFILE_NATIVE missing %s (run tools/native_ai_profile.py)" % trace_path)
		quit(1)
		return
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(trace_path))
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("local/ai/index.json")))
	_check(_sha256(FileAccess.get_file_as_bytes(root.path_join("local/ai/index.json"))) == trace.index_sha256, "index",
		"local/ai/index.json differs from the trace input")
	var real_units := []
	for unit: Dictionary in index.units:
		real_units.append({"unitname": unit.unitname, "category": unit.category, "ai_weight": unit.ai_weight,
			"ai_limit": unit.ai_limit, "downloadable": AIProfile.atoi(AIProfile.bytes_of(str(unit.downloadable) if unit.downloadable != null else "0")) & 1})
	var console_names := []
	for key in index.console_commands:
		if not key in ["plan", "weight", "limit"]:
			console_names.append(index.console_commands[key].name)
	var file_cache := {}
	for path in trace.file_hashes:
		var data := FileAccess.get_file_as_bytes(root.path_join(path))
		_check(_sha256(data) == trace.file_hashes[path], path, "profile file hash differs from the trace input")
		file_cache[path] = data
	var fault_cases := 0
	var group_counts := {}
	for case: Dictionary in trace.cases:
		var label: String = case.name
		group_counts[case.group] = group_counts.get(case.group, 0) + 1
		var profile = AIProfile.new()
		profile.setup(real_units if case.units == "real" else trace.unit_sets[case.units], console_names)
		var names := []
		for name in profile.type_names:
			names.append(AIProfile.text_of(name))
		_check(names == case.type_names, label, "type id order differs")
		profile.set_players(case.players)
		profile.difficulty = int(case.difficulty)
		profile.profile_name = case.profile_name
		for name in case.files:
			profile.files[str(name).to_lower()] = _file_bytes(case.files[name], file_cache)
		var results: Array = case.results
		var fault_operation := -1
		if case.has("fault"):
			fault_operation = int(case.fault.operation)
			fault_cases += 1
		for op_index in case.operations.size():
			var operation: Array = case.operations[op_index]
			var kind: String = operation[0]
			profile.events = []
			if kind == "set_file":
				profile.files[str(operation[1]).to_lower()] = _file_bytes(operation[2], file_cache)
				continue
			if kind == "difficulty":
				profile.difficulty = int(operation[1])
				continue
			if kind == "players":
				profile.set_players(operation[1])
				continue
			var ok: bool = profile.load_profile() if kind == "load" else profile.reload_profiles()
			if op_index == fault_operation:
				_check(not ok, label, "native faulted (%s at %s) but the port completed" % [case.fault.error, case.fault.eip])
				var native_kind := str(case.fault.get("kind", "unclassified"))
				_check(native_kind != "unclassified", label, "native fault at %s is unclassified" % case.fault.eip)
				if not ok:
					_check(profile.fault.kind == native_kind, label, "fault kind %s != native %s (eip %s)" % [
						profile.fault.kind, native_kind, case.fault.eip])
				break
			_check(ok, label, "port faulted %s but native completed" % [profile.fault])
			if not ok:
				break
			_compare_state(label + "#%d" % op_index, profile, results[op_index])
		if not case.has("fault"):
			for entry: Array in case.limit_checks:
				var allowed: bool = profile.limit_allows(int(entry[0]), int(entry[1]), int(entry[2]))
				_check(allowed == (int(entry[3]) != 0), label, "limit check %s -> %s" % [entry, allowed])
	var atof_rows := 0
	for row: Array in trace.atof:
		var text: PackedByteArray = str(row[0]).hex_decode()
		var value: float = AIProfile.atof(text)
		var bytes := PackedByteArray()
		bytes.resize(12)
		bytes.encode_double(0, value)
		bytes.encode_float(8, AIProfile.to_float32(value))
		var shown := JSON.stringify(AIProfile.text_of(text))
		_check(bytes.slice(0, 8).hex_encode() == row[1], "atof", "%s double %s != native %s" % [shown, bytes.slice(0, 8).hex_encode(), row[1]])
		_check(bytes.slice(8, 12).hex_encode() == row[2], "atof", "%s float32 %s != native %s" % [shown, bytes.slice(8, 12).hex_encode(), row[2]])
		atof_rows += 1
	for line in differences:
		print("AI_PROFILE_NATIVE mismatch ", line)
	print("AI_PROFILE_NATIVE cases %d %s, native fault cases %d, atof strings %d" % [trace.cases.size(), group_counts, fault_cases, atof_rows])
	print("AI_PROFILE_NATIVE %d / %d checks match" % [checks.x, checks.y])
	quit(0 if checks.x == checks.y and checks.y > 0 else 1)


func _file_bytes(value: Dictionary, cache: Dictionary) -> PackedByteArray:
	if value.has("hex"):
		return str(value.hex).hex_decode()
	return cache[value.path]


func _compare_state(label: String, profile, native) -> void:
	_check(profile.plan_flag == int(native.plan_flag), label, "plan flag %d != native %d" % [profile.plan_flag, native.plan_flag])
	var events = JSON.parse_string(JSON.stringify(profile.events))
	_check(_normalize(events) == _normalize(native.events), label, "events %s != native %s" % [
		JSON.stringify(profile.events).left(300), JSON.stringify(native.events).left(300)])
	for slot in AIProfile.SLOTS:
		var expected: Dictionary = native.slots[slot]
		var w: PackedByteArray = profile.weight[slot]
		_check(w.hex_encode() == expected.weight, label, "slot %d weight %s != native %s" % [slot, w.hex_encode(), expected.weight])
		_check(_ints(profile.weight_lock[slot]) == _ints(expected.weight_lock), label, "slot %d weight locks differ" % slot)
		_check(_ints(profile.limit[slot]) == _ints(expected.limit), label, "slot %d limits %s != native %s" % [slot, _ints(profile.limit[slot]), _ints(expected.limit)])
		_check(_ints(profile.limit_lock[slot]) == _ints(expected.limit_lock), label, "slot %d limit locks differ" % slot)


func _ints(values) -> Array:
	var out := []
	for v in values:
		out.append(int(v))
	return out


func _normalize(events) -> String:
	var out := []
	for event: Array in events:
		var row := []
		for item in event:
			row.append(int(item) if typeof(item) == TYPE_FLOAT else item)
		out.append(row)
	return JSON.stringify(out)
