extends SceneTree
## Compare ai_brain.gd with the original 0x408cb0 / 0x408830 (+0x480250) / 0x408c40 / 0x485a40 executions recorded by
## tools/native_ai_groups.py (local/ai/native-ai-groups.json). Adds a host_comparison block to
## analysis/native-ai-groups-validation.json.
const AIBrain = preload("res://ai_brain.gd")
const GameRandom = preload("res://wind_state.gd")

var checks := 0
var failures := 0
var mismatches: Array = []
var stats := {}

static func normalize(value: Variant) -> Variant:
	if value is Array:
		return value.map(func(item): return normalize(item))
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = normalize(value[key])
		return out
	if value is float:
		return int(value)
	return value

func check(bucket: String, host: Variant, native: Variant, context: Dictionary) -> void:
	checks += 1
	if not stats.has(bucket):
		stats[bucket] = {"checks": 0, "matched": 0}
	stats[bucket].checks += 1
	if JSON.stringify(normalize(host)) == JSON.stringify(normalize(native)):
		stats[bucket].matched += 1
		return
	failures += 1
	if mismatches.size() < 30:
		context.merge({"bucket": bucket, "host": normalize(host), "native": normalize(native)})
		mismatches.append(context)

static func unit_copies(source: Array) -> Array:
	var units: Array = []
	for index in range(source.size()):
		var unit: Dictionary = source[index]
		units.append({"flags110": int(unit.flags110), "group": int(unit.group), "type": index})
	return units

static func definitions_of(source: Array) -> Array:
	return source.map(func(unit): return {"flags241": int(unit.definition.flags241), "flags245": int(unit.definition.flags245),
		"minwaterdepth": int(unit.definition.minwaterdepth)})

func compare_assign(case_index: int, case: Dictionary) -> void:
	var units := unit_copies(case.units)
	var definitions := definitions_of(case.units)
	var lists: Array = normalize(case.group_vectors)
	var first := int(case.first)
	var last := int(case.last)
	var ids: Array = range(first, last + 1)
	var slice: Array = units.slice(first, last + 1) if last >= first else []
	var result := AIBrain.assign_groups(slice, definitions, lists, ids)
	var expected: Dictionary = case.expected
	var context := {"case": case_index, "category": case.category}
	for index in range(units.size()):
		check("assign.flags110", units[index].flags110, expected.flags110[index], context.merged({"unit": index}))
		check("assign.group", units[index].group, expected.groups[index], context.merged({"unit": index}))
	for k in range(10):
		check("assign.group_vector", lists[k], expected.group_vectors[k], context.merged({"group": k}))
	check("assign.calls", result.calls, expected.calls, context)

func compare_sequence(sequence_index: int, sequence: Dictionary) -> void:
	var rng := GameRandom.new()
	var brain := AIBrain.new(int(sequence.side), int(sequence.width), int(sequence.height), rng)
	var native: Dictionary = sequence.expected
	var built: Dictionary = native.constructed
	var context := {"sequence": sequence_index}
	check("construct.fields", [brain.player_side, brain.countdown, brain.field_9, brain.build_block_tick, brain.weapon_cursor],
		[built.side, built.countdown, built.field9, built.block_tick, built.weapon_cursor], context)
	check("construct.links", true, bool(built.player_ok), context)
	for slot in range(10):
		var native_slot = built.slots[slot]
		var handler = brain.handlers[slot]
		if native_slot == null or handler == null:
			check("construct.slot", handler == null, native_slot == null, context.merged({"slot": slot}))
			continue
		check("construct.slot", [handler.vtable, handler.think, handler.group, handler.wake, handler.side],
			[native_slot.vtable, native_slot.think, native_slot.group, native_slot.wake, native_slot.side], context.merged({"slot": slot}))
		check("construct.links", true, bool(native_slot.brain_ok) and bool(native_slot.group_offset_exact), context.merged({"slot": slot}))
		if native_slot.has("params"):
			check("construct.params", handler.params, native_slot.params, context.merged({"slot": slot}))
	brain.countdown = int(sequence.initial_countdown)
	rng.game_seed = int(sequence.seed)
	var units := unit_copies(sequence.units)
	var definitions := definitions_of(sequence.units)
	var lists: Array = [range(units.size())]
	for k in range(9):
		lists.append([])
	var perturb := {}
	for item: Array in sequence.perturb:
		perturb[int(item[0])] = int(item[1])
	var records: Array = native.records
	for offset in range(records.size()):
		var record: Dictionary = records[offset]
		if perturb.has(offset):
			rng.game_seed = perturb[offset]
		var tick_context := context.merged({"tick": int(record.tick), "offset": offset})
		check("tick.rng_before", rng.game_seed, record.rng_before, tick_context)
		var events := brain.tick(int(record.tick), {"p0": int(record.present), "type": int(record.type)}, units, definitions, lists, range(units.size()))
		var host_events: Array = []
		for event: Array in events:
			if event[0] == "think":
				host_events.append(["think", AIBrain.HANDLERS[event[1]].think, event[2], event[3]])
			else:
				host_events.append(event)
		check("tick.events", host_events, record.events, tick_context)
		check("tick.rng_after", rng.game_seed, record.rng_after, tick_context)
		check("tick.countdown", brain.countdown, record.countdown, tick_context)
		check("tick.wakes", brain.handlers.map(func(h): return null if h == null else h.wake), record.wakes, tick_context)
	var final: Dictionary = native.final_units
	check("sequence.final_flags110", units.map(func(u): return u.flags110), final.flags110, context)
	check("sequence.final_groups", units.map(func(u): return u.group), final.groups, context)
	check("sequence.final_group_vectors", lists, final.group_vectors, context)

func _init() -> void:
	var text := FileAccess.get_file_as_string("res://../local/ai/native-ai-groups.json")
	if text.is_empty():
		printerr("Missing local/ai/native-ai-groups.json; run python tools/native_ai_groups.py")
		quit(2)
		return
	var trace: Dictionary = JSON.parse_string(text)
	for index in range(trace.assign_cases.size()):
		compare_assign(index, trace.assign_cases[index])
	for index in range(trace.sequences.size()):
		compare_sequence(index, trace.sequences[index])
	var creations: Array = trace.get("creation_cases", [])
	if creations.is_empty():
		printerr("Trace has no creation_cases; rerun python tools/native_ai_groups.py")
		failures += 1
	for index in range(creations.size()):
		var case: Dictionary = creations[index]
		var definition := {"bmcode": int(case.bmcode), "flags241": int(case.flags241), "byte22e": int(case.byte22e)}
		var host := AIBrain.creation_flags(int(case.flags110), definition, int(case.owner_side) == int(case.local_side))
		check("creation.flags110", host, int(case.expected_flags110), {"creation": index})
	var path := "res://../analysis/native-ai-groups-validation.json"
	var summary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if summary is Dictionary:
		summary["host_comparison"] = {"module": "godot/ai_brain.gd", "checks": checks, "matched": checks - failures,
			"buckets": stats, "mismatches": mismatches.slice(0, 10)}
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(summary, "  ") + "\n")
	for mismatch in mismatches.slice(0, 8):
		printerr(JSON.stringify(mismatch))
	for bucket in stats:
		print("  %s: %d / %d" % [bucket, stats[bucket].matched, stats[bucket].checks])
	print("AI_GROUPS_NATIVE %d / %d checks match" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
