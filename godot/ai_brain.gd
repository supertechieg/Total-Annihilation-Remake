extends RefCounted
## Original computer-player brain plumbing (AI CP1 + CP7). See analysis/AI_BRAIN.md.
##
## Native: brain object 0x3d bytes at player+0x74, built by 0x408cb0 (called from 0x464700 at 0x4648b8),
## ticked by 0x408c40 from the per-player loop 0x464f80 (call at 0x465031, before knowledge refresh 0x40b2c0).
## Group assignment 0x408830 (every 30 brain ticks of an active type-2 player) with the 0x480250 set-group routine.
##
## Randomness: every draw goes through the shared simulation RNG 0x4b6c30 (state 0x51fc88). This module does not
## own a generator; pass the world's shared stream (res://wind_state.gd instance, `bounded_random(n)`: n < 2 returns
## 0 without advancing, else Park-Miller step then state % n), e.g. ConstructionWorld.game_random.
##
## Think bodies are CP1 stubs: each handler only executes its native prologue (wake store, including the
## rand(900)/rand(150) draws of groups 8/9 that precede it) and records the call. Later checkpoints install the
## bodies through `think_hooks[k]`, which is called AFTER the prologue with (brain, handler, tick).
##
## Unit dictionaries used by assign_groups (plain Dictionaries, mutated in place):
##   flags110: int  unit+0x110 (u32). Read: 0x20 gate, bit 29 structure (bmcode==0 at creation 0x485a81),
##                  bit 31 armed (def+0x241 bit 16, copied at creation 0x485ab3). Written: bits 18/19 move state, bits 20/21 fire state.
##   group: int     unit+0xac (s32 dword; 0 = ungrouped, -1 = dead). Any non-zero value (also 0x100) counts as grouped.
##   type: int      definition key into `definitions` (Array index or Dictionary key).
## Definition dictionaries: either raw words (flags241: int, flags245: int, minwaterdepth: int) or booleans
##   builder (def+0x241 bit 6), canfly (def+0x241 bit 11), cancapture (def+0x245 bit 12), minwaterdepth (s16 def+0x1c0,
##   FBI/moveinfo default -10000 from 0x4402e0). bmcode/weapons are NOT read by 0x408830: they only matter through
##   the unit creation flags (see creation_flags()).

const COUNTDOWN := 30
## Handler table as built by 0x408cb0 (slot k at brain+0x11+4k, slot 0 null). think = vtable[0].
## params are the dwords at handler+0x14.. exactly as stored; names follow the plan (meanings inferred).
const HANDLERS := [
	null,
	{"k": 1, "vtable": 0x4fc9b0, "think": 0x4086d0, "size": 0x14, "kind": "structures", "period": 30, "params": []},
	{"k": 2, "vtable": 0x4fc988, "think": 0x4077e0, "size": 0x28, "kind": "attack", "period": 300,
		"params": [3, 6, 20000, 3, 0], "param_names": ["min +0x14", "start +0x18", "cohesion K +0x1c", "source group +0x20", "attacking +0x24"]},
	{"k": 3, "vtable": 0x4fc990, "think": 0x4079f0, "size": 0x18, "kind": "feeder", "period": 150, "params": [2], "param_names": ["force slot +0x14"]},
	{"k": 4, "vtable": 0x4fc9a8, "think": 0x408100, "size": 0x14, "kind": "builders", "period": 90, "params": []},
	{"k": 5, "vtable": 0x4fc980, "think": 0x407380, "size": 0x14, "kind": "noop", "period": -1, "params": []},
	{"k": 6, "vtable": 0x4fc988, "think": 0x4077e0, "size": 0x28, "kind": "attack", "period": 300,
		"params": [3, 6, 50000, 7, 0], "param_names": ["min +0x14", "start +0x18", "cohesion K +0x1c", "source group +0x20", "attacking +0x24"]},
	{"k": 7, "vtable": 0x4fc990, "think": 0x4079f0, "size": 0x18, "kind": "feeder", "period": 150, "params": [6], "param_names": ["force slot +0x14"]},
	{"k": 8, "vtable": 0x4fc998, "think": 0x407ae0, "size": 0x14, "kind": "air", "period": 30, "random": 900, "params": []},
	{"k": 9, "vtable": 0x4fc9a0, "think": 0x407e90, "size": 0x3c, "kind": "hunter", "period": 30, "random": 150, "params": []},
]

var player_side := 0          ## brain+4 (player+0x146 byte), copied to handler+0x10
var countdown := COUNTDOWN    ## brain+5
var field_9 := 0              ## brain+9 (zeroed, use unknown)
var build_block_tick := 0     ## brain+0xd (commander build block, set by damage hook 0x406f80)
var weapon_cursor := 0        ## brain+0x39
var handlers: Array = []      ## index = slot 0..9; slot 0 null
var rng: Object               ## shared 0x4b6c30 stream (bounded_random / game_seed)
var think_hooks := {}         ## k -> Callable(brain, handler: Dictionary, tick: int)
var calls: Array = []         ## recorded events of the last tick() call

static func u32(value: int) -> int:
	return value & 0xffffffff

static func s32(value: int) -> int:
	value &= 0xffffffff
	return value - 0x100000000 if value & 0x80000000 else value

## x87 _ftol 0x4e43a0 of (int / 2 truncating) * 65536.0 as used by 0x407d40, low 32 bits signed.
static func half_fixed(pixels: int) -> int:
	@warning_ignore("integer_division")
	var half: int = s32(pixels) / 2
	return s32(half * 65536)

## Brain construction 0x408cb0. map_width/map_height are game+0x14223/+0x14227 (pixels), read by 0x407d40.
func _init(side: int = 0, map_width: int = 0, map_height: int = 0, random_source: Object = null) -> void:
	player_side = side & 0xff
	rng = random_source
	handlers = [null]
	for slot in range(1, 10):
		var entry: Dictionary = HANDLERS[slot]
		var handler := {"k": slot, "group": slot, "vtable": entry.vtable, "think": entry.think, "kind": entry.kind,
			"wake": 0, "side": player_side, "params": entry.params.duplicate()}
		if entry.kind == "hunter":
			# 0x407d40: +0x14, +0x20, +0x2c = (ftol(W/2*65536), 0, ftol(H/2*65536)); +0x38 = 0.
			var centre := [half_fixed(map_width), 0, half_fixed(map_height)]
			handler.params = centre + centre + centre + [0]
		handlers.append(handler)

## 0x46489d: a brain is created for a player record when [record] == 0 or type != 3.
static func creates_brain(player: Dictionary) -> bool:
	return int(player.get("p0", 0)) & 0xffffffff == 0 or int(player.get("type", 0)) & 0xff != 3

## 0x464f80 per-player filter (slots 0..9 in order): [record] != 0, type in 1..3, side byte +0x146 != 10.
## A passing player with a brain gets tick() and then (always) knowledge refresh 0x40b2c0 (not modelled here).
## type and side are bytes (only the low 8 bits are compared), p0 is a dword.
static func runs_player_step(player: Dictionary) -> bool:
	return int(player.get("p0", 0)) & 0xffffffff != 0 and int(player.get("type", 0)) & 0xff in [1, 2, 3] and int(player.get("side", 0)) & 0xff != 10

## unit+0x110 word left by the unit initialiser 0x485a40 (every store from 0x485a70 to 0x485cf1; the called
## 0x48a160/0x489800/0x401070 and the final 0x480250(unit, 0) do not touch it). flags110 is the prior word.
## definition: "bmcode" (def+0x22f byte, default 1), "flags241" (def+0x241 dword, default 0), "byte22e" (def+0x22e
## byte, default 0). local_side: owner side byte (player+0x146) == game+0x2a43.
##   0x485a70: bit 28 set; 0x485a8b: bits 29 and 14 cleared, bit 29 = (bmcode == 0).
##   0x485ab3: bit 31 = def+0x241 bit 16 (`(and 0xffff0000) shl 0xf`, only bit 16 survives).
##   0x485af3: bit 30 = def+0x241 bit 9.
##   0x485b4c: and 0xfffdf3e1, or 0x10021 (bit 0x20 is the 0x408830 gate).
##   0x485c3e: bits 8/9 cleared, bit 9 = local_side.
##   0x485c90..0x485ccd: bits 18-19 = def+0x241 bits 0-1, bits 20-21 = bits 2-3, bit 11 = bit 4, bits 26/27 cleared.
##   0x485cdb: byte22e > 1 (unsigned) -> bits 22/23 set and 24/25 cleared, else bits 22..25 cleared.
## Bit meanings beyond the AI reads (29 structure, 31 armed, 0x20 gate, 18..21 move/fire state) are unknown.
static func creation_flags(flags110: int, definition: Dictionary, local_side: bool = false) -> int:
	var flags241 := u32(int(definition.get("flags241", 0)))
	var flags := (u32(flags110) | 0x10000000) & 0xdfffbfff
	if int(definition.get("bmcode", 1)) & 0xff == 0:
		flags |= 0x20000000
	flags = (flags & 0x7fffffff) | u32((flags241 & 0xffff0000) << 15)
	flags = (flags & 0xbfffffff) | ((flags241 & 0x200) << 21)
	flags = (flags & 0xfffdf3e1) | 0x10021
	flags = (flags & 0xfffffcff) | (0x200 if local_side else 0)
	flags = (flags & 0xfff3ffff) | ((flags241 & 0x3) << 18)
	flags = (flags & 0xffcfffff) | ((flags241 & 0xc) << 18)
	flags = (flags & 0xf3fff7ff) | ((flags241 & 0x10) << 7)
	if int(definition.get("byte22e", 0)) & 0xff > 1:
		flags = (flags & 0xfcffffff) | 0xc00000
	else:
		flags &= 0xfc3fffff
	return flags

static func definition_bit(definition: Dictionary, raw: String, bit: int, name: String) -> bool:
	if definition.has(raw):
		return int(definition[raw]) & bit != 0
	return bool(definition.get(name, false))

static func short16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value & 0x8000 else value

## Group selection of 0x408830 for an ungrouped unit; 0 means "leave ungrouped" (0x480250 not called).
static func select_group(flags110: int, definition: Dictionary) -> int:
	if flags110 & 0x20000000:
		return 5 if flags110 & 0x80000000 else 1
	if definition_bit(definition, "flags241", 0x40, "builder"):
		return 4
	if definition_bit(definition, "flags241", 0x800, "canfly"):
		return 8
	if short16(int(definition.get("minwaterdepth", -10000))) > 0:
		return 7
	if flags110 & 0x80000000:
		return 3
	return 0

## Group-number writer 0x480250(unit, group): swap-remove from the old group's vector when the old group is not
## -1 and the unit is found (the last element takes its slot), append to the new group's vector unless the new
## group is -1, then store the group. group_lists: Array of 10 Arrays of unit ids, or null.
static func set_unit_group(unit: Dictionary, unit_id: Variant, group: int, group_lists: Variant) -> void:
	var old := s32(int(unit.group))
	if group_lists != null:
		if old != -1 and old >= 0 and old < group_lists.size():
			var members: Array = group_lists[old]
			var position := members.find(unit_id)
			if position >= 0:
				members[position] = members[members.size() - 1]
				members.pop_back()
		if group != -1 and group >= 0 and group < group_lists.size():
			group_lists[group].append(unit_id)
	unit.group = group

## 0x408830 over the player's own unit range (player+0x67 .. player+0x6b inclusive, array order).
## units: Array of unit Dictionaries in range order. ids: optional parallel Array of ids for group_lists.
## Returns {"flags110": [...], "groups": [...], "calls": [[id or range index, group], ...]} after mutating units.
static func assign_groups(units: Array, definitions: Variant, group_lists: Variant = null, ids: Variant = null) -> Dictionary:
	var calls_made: Array = []
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var flags := u32(int(unit.flags110))
		if flags & 0x20 == 0:
			continue
		var definition: Dictionary = definitions[unit.type]
		if definition_bit(definition, "flags245", 0x1000, "cancapture"):
			flags = (flags & 0xfff7ffff) | 0x40000   # MANEUVER; clears only bit 19
		else:
			flags = (flags & 0xfffbffff) | 0x80000   # ROAM; clears only bit 18
		flags = (flags & 0xffefffff) | 0x200000      # FIRE AT WILL; clears only bit 20
		unit.flags110 = flags
		if s32(int(unit.group)) != 0:
			continue
		var group := select_group(flags, definition)
		if group == 0:
			continue
		var unit_id: Variant = ids[index] if ids != null else index
		set_unit_group(unit, unit_id, group, group_lists)
		calls_made.append([unit_id, group])
	return {"flags110": units.map(func(u): return u32(int(u.flags110))), "groups": units.map(func(u): return s32(int(u.group))), "calls": calls_made}

## The 0x4b6c30 stream. A brain built without one reports an error and gets a private res://wind_state.gd
## instance (default seed) instead of crashing; that private stream is NOT the game's shared sequence, so native
## draw parity requires passing the world's shared stream to new().
func shared_random() -> Object:
	if rng == null:
		push_error("AIBrain: no shared 0x4b6c30 random source was passed to new(); using a private stream")
		rng = load("res://wind_state.gd").new()
	return rng

## Native prologue of each think function: the wake store at handler+0xc (u32 add of the u32 game tick).
func run_think(slot: int, tick: int) -> void:
	var handler: Dictionary = handlers[slot]
	match String(handler.kind):
		"structures", "attack", "feeder", "builders":
			handler.wake = u32(tick + int(HANDLERS[slot].period))
		"air", "hunter":
			# 0x407ae0 / 0x407e90: rand() is called BEFORE the tick is read; wake = tick + (rand + 30).
			var drawn: int = shared_random().bounded_random(int(HANDLERS[slot].random))
			handler.wake = u32(tick + drawn + 30)
		"noop":
			pass  # 0x407380 is `ret`: wake stays 0, so it is called on every brain tick.
	calls.append(["think", slot, int(handler.wake), int(rng.game_seed) if rng != null else 0])
	if think_hooks.has(slot):
		think_hooks[slot].call(self, handler, tick)

## Brain tick 0x408c40. player: {"p0": [record] dword, "type": record+0x73 byte}. tick: game+0x38a47 (u32).
## units/definitions/group_lists/ids are forwarded to assign_groups when the 30-tick countdown expires
## (units = the player's own range; pass [] if none). Returns the recorded events for this tick.
func tick(game_tick: int, player: Dictionary, units: Array = [], definitions: Variant = [], group_lists: Variant = null, ids: Variant = null) -> Array:
	calls = []
	var tick_u := u32(game_tick)
	if int(player.get("p0", 0)) & 0xffffffff != 0 and int(player.get("type", 0)) & 0xff == 2:
		countdown = s32(countdown - 1)
		if countdown <= 0:
			countdown = COUNTDOWN
			calls.append(["assign"])
			var result := assign_groups(units, definitions, group_lists, ids)
			for call: Array in result.calls:
				calls.append(["set_group", call[0], call[1]])
		for slot in range(10):
			var handler = handlers[slot]
			if handler != null and u32(int(handler.wake)) <= tick_u:
				run_think(slot, tick_u)
		calls.append(["weapons", 1])   # 0x4089a0(brain, allow_commandfire = 1): not modelled (CP14)
	else:
		calls.append(["weapons", 0])   # 0x4089a0(brain, 0)
	return calls
