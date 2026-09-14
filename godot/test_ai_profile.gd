extends SceneTree
## Self-contained unit tests for godot/ai_profile.gd (no local assets needed). Expected values come from the native
## oracle tools/native_ai_profile.py (see analysis/AI_PROFILE.md). Prints "AI_PROFILE x / y checks pass".
const AIProfile = preload("res://ai_profile.gd")

var checks := {"x": 0, "y": 0}

const UNITS := [
	{"unitname": "ARMCOM", "category": "ARM COMMANDER LEVEL1"},
	{"unitname": "ARMSOLAR", "category": "ARM ENERGY LEVEL1"},
	{"unitname": "armmex", "category": "ARM METAL"},
	{"unitname": "CORAK", "category": "CORE KBOT LEVEL1"},
	{"unitname": "CORFLAK", "category": "CORE LEVEL3", "downloadable": 1, "ai_weight": "weight CORFLAK 6", "ai_limit": "limit CORFLAK 8"},
	{"unitname": "CORDL", "category": "CORE LEVEL2", "downloadable": 1, "ai_weight": "weight LEVEL2 0.5"},
	{"unitname": "ARMMARK", "category": "ARM LEVEL2", "downloadable": 1, "ai_limit": "limit ARMMARK 2"},
	{"unitname": "CORE", "category": "ARM"},
]
const SKIRMISH := [[1, 1, 1], [1, 2, 1]]


func _check(ok: bool, what: String) -> void:
	checks.y += 1
	if ok:
		checks.x += 1
	else:
		print("AI_PROFILE FAIL ", what)


func _profile(script: String, difficulty := 0, players: Array = SKIRMISH) -> Object:
	var profile = AIProfile.new()
	profile.setup(UNITS, ["Radar", "NoShake"])
	profile.set_players(players)
	profile.difficulty = difficulty
	profile.profile_name = "ai\\test.txt"
	profile.files["ai\\test.txt"] = AIProfile.bytes_of(script)
	profile.load_profile()
	return profile


func _id(profile, name: String) -> int:
	return int(profile.name_ids[AIProfile.fold_key(AIProfile.bytes_of(name))])


func _initialize() -> void:
	var b := AIProfile.bytes_of
	# ids: _stricmp order, id 0 reserved
	var p = _profile("")
	var order := []
	for name in p.type_names:
		order.append(AIProfile.text_of(name))
	_check(order == ["", "ARMCOM", "ARMMARK", "armmex", "ARMSOLAR", "CORAK", "CORDL", "CORE", "CORFLAK"], "stricmp id order %s" % [order])
	_check(p.weight_of(1, 0) == 100 and p.limit[1][0] == -1, "defaults")
	# tokenizer
	var t := AIProfile.tokenize(b.call("  weight\tARM" + String.chr(11) + "0.5#x y"))
	_check(t.argv.size() == 3 and AIProfile.text_of(t.argv[2]) == "0.5", "tokens and mid-token #")
	_check(AIProfile.tokenize(b.call("a ".repeat(25))).argv.size() == 20, "20 argv max")
	_check(not AIProfile.tokenize(b.call("limit ARMCOM 3 " + "x".repeat(111))).overflow, "127 storage bytes fit")
	_check(AIProfile.tokenize(b.call("limit ARMCOM 3 " + "x".repeat(112))).overflow, "128 storage bytes overflow")
	# numbers
	_check(AIProfile.atoi(b.call("4294967297")) == 1 and AIProfile.atoi(b.call("-2147483649")) == 2147483647, "atoi wraps 32-bit")
	_check(AIProfile.atoi(b.call("12abc")) == 12 and AIProfile.atoi(b.call("0x10")) == 0 and AIProfile.atoi(b.call("+7")) == 7, "atoi prefix")
	_check(AIProfile.atof(b.call("1d1")) == 10.0 and AIProfile.atof(b.call(".5")) == 0.5 and AIProfile.atof(b.call("inf")) == 0.0, "atof grammar")
	_check(AIProfile.weight_result(100, AIProfile.to_float32(0.29)) == 28, "float32 0.29 truncates to 28")
	# CRT atof bit patterns recorded from 0x4e4560 in the oracle (little-endian double hex)
	for entry in [["0.0000000000000000005e19", "0000000000001440"], ["1.9703343510627747", "000000507d86ff3f"],
			["0.0000000000000000000096e51", "b2425a78d14a5e46"], ["9999999999999999999999995", "9102282c2a8b2045"],
			["4.9406564584124654e-324", "0200000000000000"], ["2.4703282292062328e-324", "0000000000000000"],
			["1e5201", "000000000000f07f"], ["-0", "0000000000000080"], ["5e", "0000000000001440"],
			["123456789012345678901234567890", "3e376cff90eef845"], ["1.7976931348623158e308", "ffffffffffffef7f"],
			# 25th digit bumps digit 24 (0x4f4203); the 24-digit midpoint alone truncates
			["713463255249263272132608.1", "e2db47759de2e244"], ["713463255249263272132608", "e1db47759de2e244"],
			# __ld12mul guard word exactly 0x8000 with bit 16 clear is not rounded up (0x4f92cf)
			["1646513063411645e13", "561b1884d199ca45"],
			# exponent digits capped at 5201 before the 5001 leading-zero adjustment (0x4f412a): 1e200, not 1e299
			["0." + "0".repeat(5000) + "1e5300", "5a62d7d718e77469"]]:
		var encoded := PackedByteArray()
		encoded.resize(8)
		encoded.encode_double(0, AIProfile.atof(b.call(entry[0])))
		_check(encoded.hex_encode() == entry[1], "atof %s -> %s (native %s)" % [entry[0], encoded.hex_encode(), entry[1]])
	_check(AIProfile.weight_result(100, AIProfile.to_float32(3e7)) == 0, "fistp64 low 32 bits negative -> 0")
	_check(AIProfile.weight_result(100, AIProfile.to_float32(1e9)) == 100, "fistp64 low 32 bits positive -> 100")
	_check(AIProfile.weight_result(100, AIProfile.to_float32(1e19)) == 0, "fistp64 overflow -> indefinite -> 0")
	_check(AIProfile.weight_result(37, -1.0) == 0, "negative clamps to 0")
	# wildcard 0x4bc370
	_check(AIProfile.wildcard_match(b.call("ARMCOM"), b.call("arm*")), "wildcard star")
	_check(AIProfile.wildcard_match(b.call("CORAK"), b.call("?ORAK")) and not AIProfile.wildcard_match(b.call("CORAK"), b.call("?ORA")), "wildcard ?")
	_check(AIProfile.wildcard_match(b.call("A"), b.call("***a")) and not AIProfile.wildcard_match(b.call("AB"), b.call("A?*B*")), "wildcard stars")
	_check(AIProfile.wildcard_match(b.call("ARMCOM"), b.call("******OM")) and AIProfile.wildcard_match(b.call("armmex"), b.call("A******X")),
		"wildcard 100-state cap (native boundary case)")
	var sorted_ids = AIProfile.new()
	sorted_ids.setup([{"unitname": "ARMA"}, {"unitname": "ARM_X"}])
	_check(AIProfile.text_of(sorted_ids.type_names[1]) == "ARM_X", "_stricmp folds to lower case: '_' sorts before 'a'")
	# lines, comments, case
	p = _profile("WEIGHT arm 0.5\r\n// weight ARM 0\n#weight LEVEL1 0\nweight LEVEL1 0.5 # trailing")
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 25 and p.weight_of(1, _id(p, "CORAK")) == 50, "case, CRLF, comments")
	_check(p.events.has(["script_file", "debugdat\\//.txt"]), "// is an unknown command")
	p = _profile("weight ARM 0.5\rweight KBOT 0.25")
	_check(p.weight_of(1, _id(p, "CORAK")) == 100 and p.weight_of(1, _id(p, "ARMCOM")) == 50, "bare CR does not split lines")
	# plan
	p = _profile("plan easy\nweight ARM 0.5\nplan hard any\nweight KBOT 0.5\nplan any hard\nlimit ALL 4", 0)
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 50, "plan easy on easy")
	_check(p.weight_of(1, _id(p, "CORAK")) == 100, "plan hard any: argv[2] any ignored")
	_check(p.limit[1][_id(p, "CORAK")] == 4, "plan any hard: argv[1] any")
	p = _profile("plan medium\nweight ARM 0.5\nplan hard\nweight KBOT 0.5", 1)
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 50 and p.weight_of(1, _id(p, "CORAK")) == 100, "difficulty 1 is medium")
	p = _profile("plan\nweight ARM 0.5")
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 100 and p.plan_flag == 1, "bare plan switches off; FBI pass forces flag 1")
	# locks and resolution
	p = _profile("weight ARMCOM 0.5\nweight ARM 0.5\nweight ARMCOM 0.1\nlimit ARM 9\nlimit ARMCOM 3\nlimit ARM 1")
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 50 and p.weight_lock[1][_id(p, "ARMCOM")] == 1, "explicit weight locks first")
	_check(p.weight_of(1, _id(p, "ARMSOLAR")) == 50 and p.weight_lock[1][_id(p, "ARMSOLAR")] == 0, "category weight does not lock")
	_check(p.limit[1][_id(p, "ARMCOM")] == 3 and p.limit[1][_id(p, "ARMSOLAR")] == 1, "limit lock only for explicit")
	p = _profile("weight CORE 0.5\nweight nope 0\nweight ALL 0.8")
	_check(p.weight_of(1, _id(p, "CORE")) == 50 and p.weight_lock[1][_id(p, "CORE")] == 1, "unit name wins over category CORE")
	_check(p.weight_of(1, _id(p, "CORAK")) == 80, "unknown name is empty set; implicit ALL")
	p = _profile("weight ARM 0.29\nweight KBOT 0.0000000000000000005e18")
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 28 and p.weight_of(1, _id(p, "CORAK")) == 50, "weight path: CRT atof narrowed to float32")
	p = _profile("weight ARM 0.7")
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 69, "weight path narrows to float32 before the product (double 0.7 would give 70)")
	p = _profile("weight ARM\nlimit LEVEL1")
	_check(p.weight_of(1, _id(p, "ARMCOM")) == 0 and p.limit[1][_id(p, "CORAK")] == 0, "missing value -> 0")
	# players: weight for AI-object slots, limit for present type-2 slots
	p = _profile("limit ALL 5\nweight ALL 0.5", 0, [[1, 1, 1], [1, 2, 1], [1, 2, 0], [0, 2, 1]])
	_check(p.limit[0][1] == -1 and p.limit[1][1] == 5 and p.limit[2][1] == 5 and p.limit[3][1] == -1, "limit slot rule")
	_check(p.weight_of(0, 1) == 50 and p.weight_of(2, 1) == 100 and p.weight_of(3, 1) == 50, "weight slot rule")
	# FBI passes: ai_weight twice per type-2 slot, ai_limit never
	p = _profile("", 0, [[1, 1, 1], [1, 2, 1], [1, 2, 1]])
	_check(p.limit[1][_id(p, "CORFLAK")] == -1 and p.limit[1][_id(p, "ARMMARK")] == -1, "FBI ai_limit never applied")
	_check(p.weight_of(1, _id(p, "CORFLAK")) == 100 and p.weight_lock[1][_id(p, "CORFLAK")] == 1, "FBI explicit weight locks")
	_check(p.weight_of(1, _id(p, "CORDL")) == 6, "category FBI weight applied 4 times (2 slots x 2 passes): 100*0.5^4")
	p = _profile("weight CORDL 0.5", 0)
	_check(p.weight_of(1, _id(p, "ARMMARK")) == 50, "0x40a040 skips limit-locked (not weight-locked) types")
	var plan_units := [{"unitname": "ARMAMPH", "category": "LEVEL2", "downloadable": 1, "ai_weight": "plan hard"},
		{"unitname": "CORDL", "category": "LEVEL2", "downloadable": 1, "ai_weight": "weight LEVEL2 0.5"}]
	p = AIProfile.new()
	p.setup(plan_units)
	p.set_players(SKIRMISH)
	p.load_profile()
	_check(p.weight_of(1, 2) == 100 and p.plan_flag == 0, "FBI passes set the plan flag once, not per type")
	p = _profile("weight CORFLAK 0.5", 0)
	_check(p.weight_of(1, _id(p, "CORFLAK")) == 50, "profile explicit line beats FBI")
	# fallback and console
	p = _profile("Radar 1\ncor* 3\nweird")
	_check(p.events.has(["console", "Radar", ["Radar", "1"]]), "console command recorded")
	_check(p.events.has(["spawn", 3, _id(p, "CORAK")]) and p.events.has(["script_file", "debugdat\\weird.txt"]), "fallback spawn / script")
	p = _profile("ARMCOM")
	_check(p.events.has(["spawn", 0, _id(p, "ARMCOM")]), "fallback owner defaults to 0")
	p = _profile("z".repeat(47))
	_check(p.fault != null and p.fault.kind == "fallback_path_overflow", "fallback buffer overflow fault")
	_check(_profile("z".repeat(46)).fault == null, "46-character unknown command fits")
	# limit test, reload, default fallback
	p = _profile("limit CORAK 2")
	_check(p.limit_allows(1, _id(p, "CORAK"), 1) and not p.limit_allows(1, _id(p, "CORAK"), 2), "count < limit")
	_check(p.limit_allows(1, _id(p, "ARMCOM"), 999) and not p.limit_allows(1, 0, 0) and p.limit_allows(1, 0x10000 + 1, 0), "limit id word")
	p = _profile("weight ALL 0.5\nplan hard", 0, [[1, 1, 1]])
	p.reload_profiles()
	_check(p.weight_of(0, 1) == 50 and p.plan_flag == 0, "reload: no AI slot reset; plan flag persists and blocks")
	p = AIProfile.new()
	p.setup(UNITS)
	p.set_players(SKIRMISH)
	p.files["ai\\test.txt"] = PackedByteArray()
	p.files["ai\\default.txt"] = b.call("weight ARM 0.5")
	p.profile_name = "ai\\test.txt"
	p.load_profile()
	_check(p.events.size() == 1 and p.weight_of(1, 1) == 100, "an existing empty profile does not fall back to default")
	_check(not p.limit_allows(10, 1, 0) and p.fault.kind == "unmodelled_limit_slot", "slot >= 10 is reported as unmodelled")
	p = AIProfile.new()
	p.setup(UNITS)
	p.set_players(SKIRMISH)
	p.profile_name = "ai\\missing.txt"
	p.files["ai\\default.txt"] = b.call("weight ARM 0.5")
	p.load_profile()
	_check(p.events[0] == ["load_file", "ai\\missing.txt", false] and p.events[1] == ["load_file", "ai\\default.txt", true] and p.weight_of(1, 1) == 50, "default fallback")
	print("AI_PROFILE %d / %d checks pass" % [checks.x, checks.y])
	quit(0 if checks.x == checks.y else 1)
