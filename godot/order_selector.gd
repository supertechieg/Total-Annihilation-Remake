extends RefCounted
## Order and cursor selection for the player's command input: TotalA.exe order selector 0x43f0e0, cursor selector 0x43e490,
## cursor aggregation 0x48d220, the predicates canRepair 0x4899b0 / canReclaimUnit 0x489960 / canLoad 0x489a90, the inline
## featureVisible test, group issue 0x48cf30 (on top of order_queue.gd issue() = 0x43afc0) and acknowledgement 0x438880
## with its reply gate 0x47f780. Native evidence: tools/native_order_selector.py + godot/compare_native_order_selector.gd
## (see analysis/ORDER_SELECTOR.md).
##
## Pure functions over plain Dictionaries that mirror the native records (field name suffix = native offset):
##
## game g:  local_player_2a42, viewing_player_2a43, interface_37efa (1 = Right-Click interface), sea_level_1427f (byte),
##          hover_2cba (unit id, 0 none), cursor_2caa [x, y, z] 16.16, mode_2cc3 (UI order mode byte),
##          map_w_14233 / map_h_14237 (feature cells), cells_14287 [[occupant +8, back_dz +10, back_dx +11], ...] row-major,
##          feature_count_14253, feature_flags_1426f [byte +0xfe per feature definition], seen_14273 [words],
##          players [player], units [unit or null] (index = unit id, [G+0x14357] + id*0x118).
## player:  index_146, seen_w_80, seen_h_84, alliance_108 [bytes by player index], units_first_67 / units_last_6b (ids,
##          the player's unit range G+0x1b63+p*0x14b+0x67/0x6b).
## unit:    id, loco_0 (locomotion object, non-zero = mobile), weapons [3 x {flags_111, energy_c0, metal_c4}] (+0x10/+0x2c/+0x48),
##          slot1_3b, x_6a / y_6e / z_72 (16.16), transporter_86 (id), cargo_8a [ids along the +0x8a/+0x8e chain],
##          def_92 {f241, f245, footprintx_14a, buildlist_156, maxy_16e (16.16), depth_1be, minwaterdepth_1c0,
##                  weapon1_1ee {flags_111}, maxdamage_1fa, transport_size_22a, transport_capacity_22b},
##          player_96 (index into g.players; pointer identity), alive_a6, resources_ec {energy_8c, metal_98},
##          select_fb, owner_ff, build_104 (float), health_108 (word), f110.
const OrderTable = preload("res://order_table.gd")
const OrderQueue = preload("res://order_queue.gd")

const MASK32 := 0xffffffff

# Order modes (G+0x2cc3), set by the order buttons 0x419be0; 10 and 11 have no UI writer.
const MODE_DEFAULT := 1
const MODE_MOVE := 2
const MODE_ATTACK := 3
const MODE_BLAST := 4
const MODE_UNLOAD := 5
const MODE_LOAD := 6
const MODE_DEFEND := 7
const MODE_REPAIR := 8
const MODE_PATROL := 9
const MODE_STOP := 10
const MODE_TELEPORT := 11
const MODE_RECLAIM := 12
const MODE_CAPTURE := 13
const MODE_BUILD := 14

# Cursor ids (G+0x2cbe). Meanings are inferred from the selector branches.
const CURSOR_ATTACK := 0x1
const CURSOR_AIRSTRIKE := 0x2
const CURSOR_NO_ATTACK := 0x3
const CURSOR_CAPTURE := 0x4
const CURSOR_DEFEND := 0x5
const CURSOR_REPAIR := 0x6
const CURSOR_PATROL := 0x7
const CURSOR_AIR_LOAD := 0x8
const CURSOR_TELEPORT := 0x9
const CURSOR_RESURRECT := 0xa
const CURSOR_RECLAIM := 0xb
const CURSOR_LOAD := 0xc
const CURSOR_UNLOAD := 0xd
const CURSOR_MOVE := 0xe
const CURSOR_SELECT := 0xf
const CURSOR_BUILD := 0x10
const CURSOR_RC_ENEMY := 0x11
const CURSOR_RC_FRIEND := 0x12
const CURSOR_NORMAL := 0x13

# f245 / f241 bits used here.
const CAN_STAND_MOVE := 0x1
const CAN_STAND_FIRE := 0x2
const CAN_ATTACK := 0x10
const CAN_GUARD := 0x20
const CAN_PATROL := 0x40
const CAN_MOVE := 0x80
const CAN_LOAD := 0x100
const CAN_REPAIR := 0x200
const CAN_RECLAIM := 0x400
const CAN_RESURRECT := 0x800
const CAN_CAPTURE := 0x1000
const CAN_DGUN := 0x4000
const CANT_BE_TRANSPORTED := 0x80000
const IS_AIRBASE := 0x200
const CAN_FLY := 0x800
const CAN_HOVER := 0x1000
const HOVER_ATTACK := 0x8000000
const KAMIKAZE := 0x10000000
const AMPHIBIOUS := 0x200000
# f110 bits.
const U_SELECTED := 0x10
const U_SELECTABLE := 0x20
const U_NO_REPLY := 0x4000
const U_ALIVE := 0x10000000
const U_STATIONARY_ATTACKER := 0x20000000
const U_CARRIER_SELECTABLE := 0x40000000
const U_ARMED := 0x80000000
# Weapon +0x111 bits.
const W_DROPPED := 0x100
const W_WATER := 0x10000
const W_TO_AIR := 0x20000

const REPLY_ACKNOWLEDGE := 5   # 0x438880 -> 0x47f780(unit, 5, sound)


static func s16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v & 0x8000 else v


static func s32(v: int) -> int:
	v &= MASK32
	return v - 0x100000000 if v & 0x80000000 else v


static func unit(g: Dictionary, id: int):
	return g.units[id] if id > 0 and id < g.units.size() else null


static func player_of(g: Dictionary, u: Dictionary) -> Dictionary:
	return g.players[u.player_96]


static func allied(g: Dictionary, u: Dictionary, h) -> bool:
	## byte[u.player + 0x108 + byte[h.player + 0x146]] != 0 (own units are allies only when their own byte is set).
	if h == null:
		return false
	var alliance: Array = player_of(g, u).alliance_108
	var index: int = player_of(g, h).index_146 & 0xff
	return index < alliance.size() and alliance[index] != 0


static func vt(u: Dictionary, vtol: int, ground: int) -> int:
	return vtol if u.def_92.f241 & CAN_FLY else ground


static func fzero(v: float) -> bool:
	## x87 `fcomp [0.0]; fnstsw ax; test ah, 0x40` (C3): equal or unordered, so a NaN build fraction counts as finished.
	return v == 0.0 or is_nan(v)


static func height_word(v: int) -> int:
	## Integer word of a 16.16 dword (+0x70 of +0x6e, +0x170 of +0x16e).
	return s16(v >> 16)


static func selectable(g: Dictionary, h: Dictionary) -> bool:
	## Own finished selectable unit that is not carried by a transport hiding its cargo (0x43f0e0, 0x43e490, 0x48d220).
	if h.owner_ff & 0xff != g.local_player_2a42 & 0xff or h.f110 & U_SELECTABLE == 0 or not fzero(h.build_104) or h.select_fb != 0:
		return false
	var carrier = unit(g, h.transporter_86)
	return carrier == null or carrier.f110 & U_CARRIER_SELECTABLE != 0


# ---------------------------------------------------------------- predicates

static func can_repair(g: Dictionary, u: Dictionary, t) -> bool:
	## 0x4899b0.
	if t == null:
		return false
	var d: Dictionary = u.def_92
	var td: Dictionary = t.def_92
	if d.f245 & CAN_REPAIR == 0:
		return false
	if s16(t.health_108) & MASK32 == td.maxdamage_1fa & MASK32:
		return false
	if t.f110 & 3 == 2:
		return false
	var top: int = height_word(t.y_6e) + height_word(td.maxy_16e)
	var sea: int = g.sea_level_1427f & 0xff
	if d.f241 & CAN_FLY and d.f241 & AMPHIBIOUS == 0 and top < sea:
		return false
	if d.f241 & CAN_FLY:
		return true
	return top >= sea - s16(d.depth_1be)


static func can_reclaim_unit(u: Dictionary, t: Dictionary) -> bool:
	## 0x489960 (no null check on t).
	return u.def_92.f245 & CAN_RECLAIM != 0 and t.f110 & 3 != 2 and t.def_92.f245 & CAN_CAPTURE == 0


static func can_load(g: Dictionary, u: Dictionary, t: Dictionary) -> bool:
	## 0x489a90 (u = transport). No alliance test.
	var d: Dictionary = u.def_92
	var td: Dictionary = t.def_92
	if td.f245 & CANT_BE_TRANSPORTED or d.f245 & CAN_LOAD == 0:
		return false
	var carried := 0
	for id in u.cargo_8a:
		if g.units[id].transporter_86 == u.id:
			carried += 1
	if carried >= d.transport_capacity_22b & 0xff:
		return false
	if t.loco_0 == 0:
		return false
	if s16(td.footprintx_14a) > d.transport_size_22a & 0xff:
		return false
	if t.f110 & 3 == 2:
		return false
	if d.f241 & CAN_FLY == 0 and s16(td.minwaterdepth_1c0) >= 0:
		return false
	if s32(t.y_6e + td.maxy_16e) <= (g.sea_level_1427f & 0xff) << 16:
		return false
	return fzero(t.build_104)


static func cell_index(g: Dictionary, pos: Array) -> int:
	## 0x4815a0: 16-world-unit cells, -1 outside the map.
	var cx: int = s32(pos[0]) >> 20
	var cz: int = s32(pos[2]) >> 20
	if cx < 0 or cx >= s32(g.map_w_14233) or cz < 0 or cz >= s32(g.map_h_14237):
		return -1
	return cz * g.map_w_14233 + cx


static func feature_at(g: Dictionary, pos: Array) -> int:
	## Feature definition index under pos (direct occupant or 0xfffe back link), -1 for none.
	var i := cell_index(g, pos)
	if i < 0:
		return -1
	var cell: Array = g.cells_14287[i]
	var occ: int = cell[0] & 0xffff
	if occ < 0xfffb:
		return occ if occ < s32(g.feature_count_14253) else -1
	if occ != 0xfffe:
		return -1
	var back: int = g.cells_14287[i - ((cell[1] & 0xff) * g.map_w_14233 + (cell[2] & 0xff))][0] & 0xffff
	return back if back < 0xfffb else -1   # no count check on the back-linked occupant


static func feature_visible(g: Dictionary, u: Dictionary, pos: Array) -> bool:
	## Inline in 0x43f0e0/0x43e490: the viewing player's seen bit for the 32-unit square (unit's player bitmap size),
	## then a feature whose definition byte +0xfe has 0x80.
	var p: Dictionary = player_of(g, u)
	var lx: int = (s16(pos[0] >> 16) >> 5) & MASK32
	var lz: int = ((s16(pos[2] >> 16) - (s16(pos[1] >> 16) >> 1)) >> 5) & MASK32
	if lx >= p.seen_w_80 & MASK32 or lz >= p.seen_h_84 & MASK32:
		return false
	var index: int = (p.seen_w_80 * lz + lx) & 0x7fffffff   # [bitmap + index*2] wraps in 32 bits
	var word: int = g.seen_14273[index] if index < g.seen_14273.size() else 0
	if word & (1 << (g.viewing_player_2a43 & 31)) == 0:
		return false
	var f := feature_at(g, pos)
	return f >= 0 and f < g.feature_flags_1426f.size() and g.feature_flags_1426f[f] & 0x80 != 0


# ---------------------------------------------------------------- 0x43f0e0

static func order_type(g: Dictionary, mode: int, u: Dictionary, h, pos) -> int:
	## 0x43f0e0(out, mode, u, h, pos): order type id, 0 for none. A hovered unit without the alive bit gives 0 in every mode.
	## pos is the cursor world position (16.16) or null; null in mode 12 (or mode 1 routed to 12) crashes natively.
	if h != null and h.f110 & U_ALIVE == 0:
		return 0
	var d: Dictionary = u.def_92
	var f245: int = d.f245
	var f241: int = d.f241
	var mobile: bool = u.loco_0 != 0
	var ally := allied(g, u, h)
	var enemy := h != null and not ally
	match mode & 0xff:
		MODE_DEFAULT:
			if f245 & CAN_ATTACK and enemy:
				return order_type(g, MODE_ATTACK, u, h, pos)
			if g.interface_37efa == 1:
				if f245 & CAN_RECLAIM and enemy:
					return vt(u, OrderTable.OT_VTOL_RECLAIM_UNIT, OrderTable.OT_RECLAIM_UNIT)
				if ally and can_repair(g, u, h):
					if not fzero(h.build_104):
						return vt(u, OrderTable.OT_VTOL_HELP_BUILD, OrderTable.OT_HELP_BUILD)
					return vt(u, OrderTable.OT_VTOL_REPAIR_UNIT, OrderTable.OT_REPAIR_UNIT)
				if f241 & CAN_FLY and ally and h.def_92.f241 & IS_AIRBASE:
					return OrderTable.OT_VTOL_LANDING
				if h != null and can_load(g, u, h):
					return vt(u, OrderTable.OT_VTOL_PICKUP, OrderTable.OT_GROUND_PICKUP)
				if f245 & CAN_GUARD and ally:
					return vt(u, OrderTable.OT_VTOL_FOLLOW, OrderTable.OT_FOLLOW_GROUND)
			else:
				if f245 & CAN_RECLAIM and enemy:
					return order_type(g, MODE_RECLAIM, u, h, pos)
				if h != null:
					if can_repair(g, u, h) and not fzero(h.build_104):
						return order_type(g, MODE_REPAIR, u, h, pos)
					if selectable(g, h):
						return 0
			if f245 & CAN_RESURRECT and pos != null and feature_visible(g, u, pos):
				return OrderTable.OT_RESURRECT
			if f245 & CAN_RECLAIM and pos != null and feature_visible(g, u, pos):
				return vt(u, OrderTable.OT_VTOL_RECLAIM, OrderTable.OT_RECLAIM)
			if f245 & CAN_MOVE and mobile:
				return vt(u, OrderTable.OT_VTOL_MOVE, OrderTable.OT_MOVE_GROUND)
			return 0
		MODE_MOVE:
			if f245 & CAN_MOVE == 0:
				return 0
			if not mobile:
				return OrderTable.OT_QMOVE
			if h != null:
				if f245 & CAN_CAPTURE and enemy:
					return OrderTable.OT_CAPTURE
				if f245 & CAN_RECLAIM and enemy:
					return vt(u, OrderTable.OT_VTOL_RECLAIM_UNIT, OrderTable.OT_RECLAIM_UNIT)
				if ally and can_repair(g, u, h) and not fzero(h.build_104):
					return vt(u, OrderTable.OT_VTOL_HELP_BUILD, OrderTable.OT_HELP_BUILD)
				if ally and can_repair(g, u, h) and s16(h.health_108) & MASK32 < h.def_92.maxdamage_1fa & MASK32:
					return vt(u, OrderTable.OT_VTOL_REPAIR_UNIT, OrderTable.OT_REPAIR_UNIT)
				if f241 & CAN_FLY and ally and h.def_92.f241 & IS_AIRBASE:
					return OrderTable.OT_VTOL_LANDING
				if can_load(g, u, h):
					return vt(u, OrderTable.OT_VTOL_PICKUP, OrderTable.OT_GROUND_PICKUP)
				if f245 & CAN_GUARD and ally:
					return vt(u, OrderTable.OT_VTOL_FOLLOW, OrderTable.OT_FOLLOW_GROUND)
			return vt(u, OrderTable.OT_VTOL_MOVE, OrderTable.OT_MOVE_GROUND)
		MODE_ATTACK:
			return _attack_type(g, u, h, enemy)
		MODE_BLAST:
			return OrderTable.OT_ATTACK_SPECIAL if f245 & CAN_DGUN else 0
		MODE_UNLOAD:
			if f245 & CAN_LOAD and f241 & CAN_FLY and h != null and h.def_92.f241 & IS_AIRBASE:
				return OrderTable.OT_VTOL_LANDING
			if f245 & CAN_LOAD:
				return vt(u, OrderTable.OT_VTOL_UNLOAD, OrderTable.OT_GROUND_UNLOAD)
			return 0
		MODE_LOAD:
			if h != null and can_load(g, u, h):
				return vt(u, OrderTable.OT_VTOL_PICKUP, OrderTable.OT_GROUND_PICKUP)
			return 0
		MODE_DEFEND:
			if f245 & CAN_GUARD and ally:
				return vt(u, OrderTable.OT_VTOL_FOLLOW, OrderTable.OT_FOLLOW_GROUND)
			return 0
		MODE_REPAIR:
			if not can_repair(g, u, h):
				return 0
			if fzero(h.build_104):
				return vt(u, OrderTable.OT_VTOL_REPAIR_UNIT, OrderTable.OT_REPAIR_UNIT)
			return vt(u, OrderTable.OT_VTOL_HELP_BUILD, OrderTable.OT_HELP_BUILD)
		MODE_PATROL:
			if f245 & CAN_PATROL == 0:
				return 0
			if not mobile:
				return OrderTable.OT_QPATROL
			if f245 & CAN_REPAIR:
				return vt(u, OrderTable.OT_VTOL_REPAIR_PATROL, OrderTable.OT_REPAIR_PATROL)
			return vt(u, OrderTable.OT_VTOL_PATROL, OrderTable.OT_PATROL)
		MODE_STOP:
			return OrderTable.OT_STOP
		MODE_TELEPORT:
			return OrderTable.OT_TELEPORT
		MODE_RECLAIM:
			if f245 & CAN_RECLAIM == 0:
				return 0
			if pos == null:
				push_error("0x43f0e0 mode 12 dereferences a null position (0x4815a0)")
				return 0
			if f245 & CAN_RESURRECT and feature_visible(g, u, pos):
				return OrderTable.OT_RESURRECT
			if feature_visible(g, u, pos):
				return vt(u, OrderTable.OT_VTOL_RECLAIM, OrderTable.OT_RECLAIM)
			if h != null:
				return vt(u, OrderTable.OT_VTOL_RECLAIM_UNIT, OrderTable.OT_RECLAIM_UNIT)
			return 0
		MODE_CAPTURE:
			if f245 & CAN_CAPTURE and h != null and u.player_96 != h.player_96:
				return OrderTable.OT_CAPTURE
			return 0
		MODE_BUILD:
			if d.buildlist_156 != 0 and mobile:
				return vt(u, OrderTable.OT_VTOL_MOBILE_BUILD, OrderTable.OT_MOBILE_BUILD)
			return 0
	return 0


static func _attack_type(g: Dictionary, u: Dictionary, h, enemy: bool) -> int:
	var d: Dictionary = u.def_92
	var f241: int = d.f241
	if d.f245 & CAN_ATTACK == 0:
		return 0
	if u.f110 & U_ARMED:
		var w0: int = u.weapons[0].flags_111
		var w1_water: bool = u.slot1_3b & 2 != 0 and u.weapons[1].flags_111 & W_WATER != 0
		var bomb: bool = d.weapon1_1ee.flags_111 & W_DROPPED != 0
		if not enemy:
			if w0 & W_TO_AIR:
				return 0
			if f241 & CAN_FLY == 0:
				return OrderTable.OT_SUPPRESS
			return OrderTable.OT_AIR_STRIKE if bomb else OrderTable.OT_AIR_TO_GROUND
		if h.f110 & 3 != 2 and w0 & W_TO_AIR:
			return 0
		var depth: int = height_word(h.def_92.maxy_16e) + height_word(h.y_6e)
		if depth < g.sea_level_1427f & 0xff:
			if w0 & W_WATER == 0 and not w1_water:
				return 0
		elif f241 & CAN_HOVER:
			if w0 & W_WATER or w1_water:
				return 0
		if f241 & CAN_FLY:
			var target_air: bool = h.def_92.f241 & CAN_FLY != 0
			if bomb and not target_air:
				return OrderTable.OT_AIR_STRIKE
			if not bomb and target_air:
				return OrderTable.OT_AIR_TO_AIR
			if not target_air:
				return OrderTable.OT_AIR_TO_GROUND_HOVER if f241 & HOVER_ATTACK else OrderTable.OT_AIR_TO_GROUND
			return 0
		if u.loco_0 != 0:
			return OrderTable.OT_ATTACK_CHASE
		if u.f110 & U_STATIONARY_ATTACKER:
			return OrderTable.OT_ATTACK_NO_MOVE
	return OrderTable.OT_ATTACK_KAMIKAZE if f241 & KAMIKAZE else 0


# ---------------------------------------------------------------- 0x43e490

static func cursor_id(g: Dictionary, mode: int, u: Dictionary, h, pos: Array, range_unit := Callable(), range_pos := Callable()) -> int:
	## 0x43e490(mode, u, h, pos). No alive gate on h. range_unit(u, h, slot) -> bool stands for 0x49abb0 and
	## range_pos(u, pos, slot) -> bool for 0x49aa80(u, &u.pos, pos, slot); both are only reached for immobile attackers.
	var d: Dictionary = u.def_92
	var f245: int = d.f245
	var mobile: bool = u.loco_0 != 0
	var ally := allied(g, u, h)
	var enemy := h != null and not ally
	match mode & 0xff:
		MODE_DEFAULT:
			if g.interface_37efa == 1:
				if h != null and selectable(g, h):
					return CURSOR_SELECT
				if enemy:
					return CURSOR_RC_ENEMY
				if ally:
					return CURSOR_RC_FRIEND
				if f245 & CAN_RESURRECT and feature_visible(g, u, pos):
					return CURSOR_RC_FRIEND
				if f245 & CAN_RECLAIM and feature_visible(g, u, pos):
					return CURSOR_RC_FRIEND
				return CURSOR_NORMAL
			if f245 & CAN_ATTACK and enemy:
				return cursor_id(g, MODE_ATTACK, u, h, pos, range_unit, range_pos)
			if f245 & CAN_RECLAIM and enemy:
				return cursor_id(g, MODE_RECLAIM, u, h, pos, range_unit, range_pos)
			if h != null:
				if can_repair(g, u, h) and not fzero(h.build_104):
					return CURSOR_REPAIR
				if selectable(g, h):
					return CURSOR_SELECT
			if f245 & CAN_RESURRECT and feature_visible(g, u, pos):
				return CURSOR_RESURRECT
			if f245 & CAN_RECLAIM and feature_visible(g, u, pos):
				return CURSOR_RECLAIM
			return CURSOR_MOVE if f245 & CAN_MOVE else CURSOR_NORMAL
		MODE_MOVE:
			if f245 & CAN_MOVE == 0:
				return CURSOR_NORMAL
			if f245 & CAN_RESURRECT and feature_visible(g, u, pos):
				return CURSOR_RESURRECT
			if h != null and mobile:
				if f245 & CAN_CAPTURE:
					if enemy:
						return CURSOR_CAPTURE
				elif enemy and can_reclaim_unit(u, h):
					return CURSOR_RECLAIM
				if ally and can_repair(g, u, h):
					return CURSOR_REPAIR
				if d.f241 & CAN_FLY and h.def_92.f241 & IS_AIRBASE:
					return CURSOR_UNLOAD
				if can_load(g, u, h):
					return CURSOR_AIR_LOAD if d.f241 & CAN_FLY else CURSOR_LOAD
				if f245 & CAN_GUARD and ally:
					return CURSOR_DEFEND
			return CURSOR_MOVE
		MODE_ATTACK:
			if f245 & CAN_ATTACK and d.weapon1_1ee.flags_111 & W_DROPPED:
				return CURSOR_AIRSTRIKE
			if f245 & CAN_ATTACK == 0:
				return CURSOR_NORMAL
			if mobile:
				return CURSOR_ATTACK
			if h != null:
				return CURSOR_ATTACK if range_unit.call(u, h, 0) else CURSOR_NO_ATTACK
			if not range_pos.call(u, pos, 0):
				return CURSOR_NO_ATTACK
			return CURSOR_NO_ATTACK if u.weapons[0].flags_111 & W_TO_AIR else CURSOR_ATTACK
		MODE_BLAST:
			if f245 & CAN_DGUN == 0:
				return CURSOR_NORMAL
			# float compares (C0): less or unordered gives 3; NaN is covered by the oracle's edge phase
			if not (u.resources_ec.energy_8c >= u.weapons[2].energy_c0):
				return CURSOR_NO_ATTACK
			if not (u.resources_ec.metal_98 >= u.weapons[2].metal_c4):
				return CURSOR_NO_ATTACK
			return CURSOR_ATTACK
		MODE_UNLOAD:
			return CURSOR_UNLOAD if f245 & CAN_LOAD else CURSOR_NORMAL
		MODE_LOAD:
			if h != null and can_load(g, u, h):
				return CURSOR_AIR_LOAD if d.f241 & CAN_FLY else CURSOR_LOAD
			return CURSOR_NORMAL
		MODE_DEFEND:
			if f245 & CAN_GUARD == 0 or not ally:
				return CURSOR_NORMAL
			if d.f241 & CAN_FLY:
				return CURSOR_DEFEND
			return CURSOR_NORMAL if h.def_92.f241 & CAN_FLY else CURSOR_DEFEND
		MODE_REPAIR:
			return CURSOR_REPAIR if can_repair(g, u, h) else CURSOR_NORMAL
		MODE_PATROL:
			return CURSOR_PATROL if f245 & CAN_PATROL else CURSOR_NORMAL
		MODE_TELEPORT:
			return CURSOR_TELEPORT
		MODE_RECLAIM:
			if f245 & CAN_RECLAIM and feature_visible(g, u, pos):
				return CURSOR_RECLAIM
			if h != null and can_reclaim_unit(u, h):
				return CURSOR_RECLAIM
			return CURSOR_NORMAL
		MODE_CAPTURE:
			if f245 & CAN_CAPTURE and h != null and u.player_96 != h.player_96:
				return CURSOR_CAPTURE
			return CURSOR_NORMAL
		MODE_BUILD:
			return CURSOR_BUILD if d.buildlist_156 != 0 and mobile else CURSOR_NORMAL
	return CURSOR_NORMAL


static func selected_units(g: Dictionary) -> Array:
	## The local player's unit range with f110 & 0x10, in id order (0x48d220 / 0x48cf30 loops).
	var p: Dictionary = g.players[g.local_player_2a42 & 0xff]
	var out := []
	for id in range(p.units_first_67, p.units_last_6b + 1):
		var s = unit(g, id)
		if s != null and s.f110 & U_SELECTED:
			out.append(s)
	return out


static func aggregate_cursor(g: Dictionary, mode: int, range_unit := Callable(), range_pos := Callable()) -> int:
	## 0x48d220(mode): minimum (signed, capped at 0x13) of 0x43e490 over the selection without the hovered unit, which is
	## always passed. The per-unit mode is the UI mode byte G+0x2cc3, not the argument; the argument only decides the
	## empty-selection result (0xf for mode 1 over a selectable hover, else 0x13; no alive test).
	var h = unit(g, g.hover_2cba & 0xffff)
	var list := selected_units(g)
	if h != null:
		# 0x480100: the last element is moved into the removed slot (this reorders the 0x43e490 calls).
		for i in list.size():
			if list[i].id == h.id:
				list[i] = list.back()
				list.pop_back()
				break
	if list.is_empty():
		return CURSOR_SELECT if mode & 0xff == MODE_DEFAULT and h != null and selectable(g, h) else CURSOR_NORMAL
	var best := CURSOR_NORMAL
	for s in list:
		best = mini(best, cursor_id(g, g.mode_2cc3 & 0xff, s, h, g.cursor_2caa, range_unit, range_pos))
	return best


# ---------------------------------------------------------------- 0x48cf30

static func hover_excluded(mode: int, type_id: int) -> bool:
	## 0x48cf30 hover handling: with a mode, 0x43e470 (every mode but 5, 10, 14); in mode 0 the type's static 0x200.
	if mode & 0xff:
		return not (mode & 0xff in [MODE_UNLOAD, MODE_STOP, MODE_BUILD])
	return OrderTable.flags(type_id & 0xff) & OrderTable.F_TARGET != 0


static func group_issue(g: Dictionary, queues: Dictionary, input_flags: int, mode: int, type_id: int, pos, p5: int, p6: int, ids = null, observer := Callable()) -> Array:
	## 0x48cf30(input, mode, type, pos, p5, p6). queues maps unit id -> OrderQueue; ids is an optional {next} Dictionary
	## shared by all queues for order allocation ids; observer(unit id, type dword, shift, target id, pos, p5, p6) sees each
	## 0x43afc0 call. Returns [[unit id, type, issued order or null], ...] per recipient.
	## Modes pick a per-unit type with 0x43f0e0 at the cursor position (not pos); formation types (static 0x2) spread pos
	## by each unit's offset from the selection centre when that offset is within n*3000 (squared world units).
	var shift: bool = (input_flags >> 2) & 1 != 0
	var h = null
	if hover_excluded(mode, type_id) and g.hover_2cba & 0xffff:
		h = unit(g, g.hover_2cba & 0xffff)
	var p: Dictionary = g.players[g.local_player_2a42 & 0xff]
	var first: int = p.units_first_67
	var last: int = p.units_last_6b
	var n := 0
	var sx := 0
	var sz := 0
	for id in range(first, last + 1):
		var s = unit(g, id)
		if s == null or s.f110 & U_SELECTED == 0 or (h != null and s.id == h.id):
			continue
		n += 1
		sx = s32(sx + s16(s.x_6a >> 16))
		sz = s32(sz + s16(s.z_72 >> 16))
	var issued := []
	if n == 0:
		return issued
	var cx: int = s32(_idiv(sx, n) << 16)
	var cz: int = s32(_idiv(sz, n) << 16)
	var limit: int = s32(n * 3000)
	for id in range(first, last + 1):
		var s = unit(g, id)
		if s == null or s.f110 & U_SELECTED == 0 or (h != null and s.id == h.id):
			continue
		var t: int
		if mode & 0xff:
			t = (type_id & ~0xff) | order_type(g, mode, s, h, g.cursor_2caa)
		else:
			t = type_id
		var tb := t & 0xff
		if tb == 0:
			continue
		if tb == OrderTable.OT_STANDING_FIRE_ORDER and s.def_92.f245 & CAN_STAND_FIRE == 0:
			continue
		if tb == OrderTable.OT_STANDING_MOVE_ORDER and s.def_92.f245 & CAN_STAND_MOVE == 0:
			continue
		var at = pos
		if pos != null and OrderTable.flags(tb) & OrderTable.F_FORMATION:
			var dx: int = s32(s.x_6a - cx)
			var dz: int = s32(s.z_72 - cz)
			var dist: int = s32(((dx * dx) >> 32) + ((dz * dz) >> 32))
			if dist <= limit:
				at = [s32(pos[0] + s.x_6a - cx), pos[1], s32(pos[2] + s.z_72 - cz)]
		var target: int = h.id if h != null else 0
		if observer.is_valid():
			observer.call(s.id, t & MASK32, 1 if shift else 0, target, at, p5, p6)
		var q = queues[s.id]
		if ids != null:
			q.next_id = ids.next
		var order = q.issue(tb, shift, target, at, p5, p6)
		if ids != null:
			ids.next = q.next_id
		issued.append([s.id, tb, order])
	return issued


static func _idiv(a: int, b: int) -> int:
	## x86 idiv: truncation toward zero.
	var q: int = absi(a) / absi(b)
	return -q if (a < 0) != (b < 0) else q


# ---------------------------------------------------------------- acknowledgement

static func acknowledge(g: Dictionary, u: Dictionary, order: Dictionary, sound = null) -> Array:
	## 0x438880(order, sound): a pending 0x2000 is cleared and 0x47f780(unit, 5, sound) replies only for a live unit of
	## the viewing player without f110 0x4000. Returns [unit id, 5, sound] when a reply is queued, else [].
	## sound null means the reply table default (0x5086e8 + 5*0x18, filled at runtime).
	if order.flags & OrderTable.R_ACKNOWLEDGE == 0:
		return []
	order.flags &= ~OrderTable.R_ACKNOWLEDGE
	if u.owner_ff & 0xff != g.viewing_player_2a43 & 0xff or u.f110 & U_ALIVE == 0 or u.f110 & U_NO_REPLY:
		return []
	return [u.id, REPLY_ACKNOWLEDGE, sound]
