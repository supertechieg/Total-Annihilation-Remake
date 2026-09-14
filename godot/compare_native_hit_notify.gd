extends SceneTree
## Compare damage_notify.gd with the original 0x499cd0 -> 0x489bb0 -> 0x489ce0 weapon hit path (tools/native_hit_notify.py).
## Core cases (no veterancy, game flags 0) use only DamageNotify plus the trunc(default*scale) lookup; veterancy/game-flag,
## paralyzer and inactive-owner cases add the recovered formulas inline and are reported separately.
const DamageNotify = preload("res://damage_notify.gd")
const SCRIPTS := 0x2030000

static func s32(value: int) -> int:
	value &= 0xffffffff
	return value - 0x100000000 if value & 0x80000000 else value

static func s16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value & 0x8000 else value

## Signed truncating division as compiled (imul magic, sar, add sign bit).
static func tdiv(value: int, divisor: int) -> int:
	var quotient := absi(value) / divisor
	return -quotient if value < 0 else quotient

static func ints(values: Array) -> Array:
	return values.map(func(value): return ints(value) if value is Array else int(value))

func expected(case: Dictionary) -> Dictionary:
	var target: Dictionary = case.target
	var has_attacker: bool = case.attacker != null
	var damage := int(float(case.default_damage) * float(case.scale))
	if has_attacker:
		var k := mini(int(case.attacker.veterancy) / 5, 5)
		damage = tdiv(s32((6 * k + 100) * damage), 100)
	var game_flags := int(case.game_flags)
	if game_flags & 0x80:
		damage = s32(damage + damage)
	if game_flags & 0x100:
		damage = tdiv(damage, 2)
	var returned := damage
	var kind := 2 if int(case.weapon_flags) & 0x80 else 1
	damage = DamageNotify.armored_damage(damage, bool(target.armored), int(target.modifier))
	var target_k := mini(int(target.veterancy) / 5, 5)
	damage = tdiv(s32(s32((25 - target_k) * damage) * 4), 100)
	var byte := DamageNotify.angle_byte(ints(case.projectile), ints(target.position), int(target.heading))
	var packet := {"code": 11, "target": int(target.index), "attacker": int(case.attacker.index) if has_attacker else 0,
		"damage": damage & 0xffff, "angle": byte, "type": kind}
	var health := s16(int(target.health))
	var flags := int(target.flags)
	var dying := bool(flags & 0x4000)
	var scripts: Array = []
	var owner_ok := bool(target.record_active) and int(target.record_type) in [1, 2]
	if not (flags & 0x10000000) or flags & 0x4000:
		pass  # 0x489d3f..0x489d53: not alive or already dying -> packet only
	elif kind == 2:
		pass  # def +0x241 bit 0x4000000 (or owner record not type 1/2): no health change and no paralyze order
	else:
		health = s16(health - (damage & 0xffff))
		if health <= 0 and owner_ok:
			dying = true
		else:
			if health <= 0:
				health = 0
			var object := SCRIPTS + int(target.index)
			var arguments := DamageNotify.hit_arguments(byte)
			scripts.append({"name": "HitByWeapon", "object": object, "args": [0, 0, 2, arguments[0], arguments[1], 0, 0]})
			scripts.append({"name": "TakeDamage", "object": object, "args": [0, 0, 1, DamageNotify.health_percent(health, int(target.maxdamage)), 0, 0, 0]})
	return {"returned": returned, "packet": packet, "health": health, "dying": dying, "scripts": scripts}

func normalize(value):
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = normalize(value[key])
		return result
	if value is Array:
		return value.map(func(item): return normalize(item))
	if value is float:
		return int(value)
	return value

func _initialize() -> void:
	var text := FileAccess.get_file_as_string("res://../local/combat/native-hit-notify.json")
	var trace = JSON.parse_string(text)
	if not trace is Dictionary:
		printerr("Run tools/native_hit_notify.py first")
		quit(1)
		return
	var sine := DamageNotify.table()
	var sine_matches := ints(trace.sine) == sine
	var fields := ["returned", "packet", "health", "dying", "scripts"]
	var stats := {}
	var mismatches: Array = []
	var total_checks := 0
	var total_failures := 0
	var lethal_no_script := 0
	var ordered_calls := 0
	for index in range(trace.cases.size()):
		var case: Dictionary = trace.cases[index]
		var category: String = case.category
		if not stats.has(category):
			stats[category] = {"cases": 0, "checks": 0, "matched": 0, "dying": 0, "exact_zero": 0, "scripted": 0}
		var bucket: Dictionary = stats[category]
		bucket.cases += 1
		var native: Dictionary = normalize(case.expected)
		native.dying = bool(case.expected.dying)
		var host := expected(case)
		for field: String in fields:
			bucket.checks += 1
			total_checks += 1
			if JSON.stringify(host[field]) == JSON.stringify(native[field]):
				bucket.matched += 1
			else:
				total_failures += 1
				if mismatches.size() < 20:
					mismatches.append({"case": index, "category": category, "field": field, "host": host[field], "native": native[field]})
		if native.dying and not int(case.target.flags) & 0x4000:
			bucket.dying += 1
			if native.scripts.is_empty():
				lethal_no_script += 1
		if int(native.health) == 0:
			bucket.exact_zero += 1
		if native.scripts.size() == 2 and native.scripts[0].name == "HitByWeapon" and native.scripts[1].name == "TakeDamage":
			bucket.scripted += 1
			ordered_calls += 1
	total_checks += 1
	if not sine_matches:
		total_failures += 1
	var report := {"exe_sha256": trace.exe_sha256, "oracle": "tools/native_hit_notify.py", "comparator": "godot/compare_native_hit_notify.gd",
		"cases": trace.cases.size(), "checks": total_checks, "matched": total_checks - total_failures, "sine_table_matches": sine_matches,
		"categories": stats, "lethal_without_scripts": lethal_no_script, "ordered_hit_then_take_damage": ordered_calls,
		"mismatches": mismatches, "scope": "Original 0x499cd0 (scale 1.0 and random float32 scale, null per-unit damage table) through 0x489bb0 and 0x489ce0: packet damage/angle/type, health word, dying flag 0x4000, HitByWeapon(cos400, sin400) then TakeDamage(percent) via recorded 0x4b0a70. Core cases use DamageNotify only; veterancy/game flags, paralyzer (type 2 with def+0x241 0x4000000) and inactive-owner / owner-type not 1-2 (health clamped to 0, scripts still start), gated (flags without 0x10000000 or with 0x4000: packet only) use inline recovered formulas; armor-boundary uses DamageNotify only.",
		"stubs": {"0x4b0a70": "script start recorder (thiscall ret 0x20)", "0x406f80": "damage statistics (ret 0xc)", "0x494ff0": "local-player global counter (ret 4)", "0x406f50": "kill statistics, asserted unreached", "0x451df0": "network send, asserted unreached (owner types 1/2 only)"}}
	FileAccess.open("res://../analysis/native-hit-notify-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	for mismatch in mismatches.slice(0, 8):
		printerr(JSON.stringify(mismatch))
	for category in stats:
		print("  %s: %d / %d checks (%d cases, %d dying, %d zero health, %d scripted)" % [category, stats[category].matched, stats[category].checks, stats[category].cases, stats[category].dying, stats[category].exact_zero, stats[category].scripted])
	print("HIT_NOTIFY_NATIVE %d / %d checks match (%d cases)" % [total_checks - total_failures, total_checks, trace.cases.size()])
	quit(0 if total_failures == 0 else 1)
