extends SceneTree
## Hand-built order/cursor selector and group issue scenarios (expected values read from the disassembly of 0x43f0e0,
## 0x43e490, 0x4899b0, 0x489960, 0x489a90, 0x48d220, 0x48cf30 and 0x438880). The randomized native comparison is
## compare_native_order_selector.gd.
const OrderTable = preload("res://order_table.gd")
const OrderQueue = preload("res://order_queue.gd")
const Sel = preload("res://order_selector.gd")

const T := OrderTable
const P := 0x10000   # one world unit in 16.16
const MOVE := 0x80
const ATK := 0x10
const GUARD := 0x20
const PATROL := 0x40
const LOAD := 0x100
const REP := 0x200
const RECL := 0x400
const RES := 0x800
const CAPT := 0x1000
const DGUN := 0x4000
const FLY := 0x800
const ALIVE := 0x10000000
const ARMED := 0x80000000

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func eq(got, expected, message: String) -> void:
	check(got == expected, "%s: expected %s got %s" % [message, expected, got])


func new_def(f245: int, f241 := 0) -> Dictionary:
	return {f241 = f241, f245 = f245, footprintx_14a = 2, buildlist_156 = 0, maxy_16e = 10 * P, depth_1be = 0,
		minwaterdepth_1c0 = -10000, weapon1_1ee = {flags_111 = 0}, maxdamage_1fa = 100, transport_size_22a = 4,
		transport_capacity_22b = 2}


func new_unit(id: int, player: int, def: Dictionary, f110 := ALIVE, loco := 1) -> Dictionary:
	return {id = id, loco_0 = loco, weapons = [{flags_111 = 0, energy_c0 = 0.0, metal_c4 = 0.0}, {flags_111 = 0, energy_c0 = 0.0, metal_c4 = 0.0},
		{flags_111 = 0, energy_c0 = 0.0, metal_c4 = 0.0}], slot1_3b = 0, x_6a = 0, y_6e = 0, z_72 = 0, transporter_86 = 0,
		cargo_8a = [], def_92 = def, player_96 = player, alive_a6 = 1, resources_ec = {energy_8c = 0.0, metal_98 = 0.0},
		select_fb = 0, owner_ff = player, build_104 = 0.0, health_108 = 100, f110 = f110}


func new_game() -> Dictionary:
	# player 0 (local, viewer) allied with itself and player 1; player 2 is an enemy
	var players := []
	for i in 3:
		players.append({index_146 = i, seen_w_80 = 8, seen_h_84 = 8, alliance_108 = [1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
			units_first_67 = 1, units_last_6b = 0})
	players[2].alliance_108 = [0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
	var cells := []
	for i in 64:
		cells.append([0xffff, 0, 0])
	var seen := []
	seen.resize(64)
	seen.fill(0xffff)
	return {local_player_2a42 = 0, viewing_player_2a43 = 0, interface_37efa = 0, sea_level_1427f = 0, hover_2cba = 0,
		cursor_2caa = [40 * P, 0, 40 * P], mode_2cc3 = 1, map_w_14233 = 8, map_h_14237 = 8, cells_14287 = cells,
		feature_count_14253 = 2, feature_flags_1426f = [0x80, 0x00, 0x80, 0x80], seen_14273 = seen, players = players,
		units = [null]}


func add(g: Dictionary, u: Dictionary) -> Dictionary:
	while g.units.size() <= u.id:
		g.units.append(null)
	g.units[u.id] = u
	return u


func _initialize() -> void:
	test_hover_gate()
	test_mode1_left()
	test_mode1_right()
	test_mode2()
	test_mode3()
	test_other_modes()
	test_predicates()
	test_feature_visible()
	test_aggregate()
	test_group_issue()
	test_acknowledge()
	test_nan_floats()
	print("ORDER_SELECTOR %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func test_nan_floats() -> void:
	# x87 fcomp against 0.0 then `test ah, 0x40` (C3) is also set for unordered: a NaN build fraction reads as finished.
	var g := new_game()
	var builder := add(g, new_unit(1, 0, new_def(MOVE | REP | DGUN)))
	var own := add(g, new_unit(2, 0, new_def(MOVE), ALIVE | 0x20))
	own.build_104 = NAN
	own.health_108 = 10
	eq(Sel.fzero(NAN), true, "NaN counts as zero")
	eq(Sel.cursor_id(g, 1, builder, own, g.cursor_2caa), Sel.CURSOR_SELECT, "NaN-build own unit is selectable")
	eq(Sel.order_type(g, 1, builder, own, g.cursor_2caa), 0, "NaN-build own unit: left click selects (no help build)")
	eq(Sel.order_type(g, 8, builder, own, g.cursor_2caa), T.OT_REPAIR_UNIT, "mode 8 on a NaN-build unit repairs")
	var truck := add(g, new_unit(3, 0, new_def(MOVE | LOAD)))
	own.y_6e = 20 * P
	eq(Sel.can_load(g, truck, own), true, "canLoad accepts a NaN build fraction")
	builder.resources_ec.energy_8c = NAN
	eq(Sel.cursor_id(g, 4, builder, null, g.cursor_2caa), Sel.CURSOR_NO_ATTACK, "D-gun cursor: unordered energy compare gives 3")


func test_hover_gate() -> void:
	var g := new_game()
	var u := add(g, new_unit(1, 0, new_def(MOVE | ATK | GUARD)))
	var h := add(g, new_unit(2, 2, new_def(MOVE), 0))
	for mode in [1, 2, 3, 10, 11]:
		eq(Sel.order_type(g, mode, u, h, g.cursor_2caa), 0, "dead hover gives no order in mode %d" % mode)
	eq(Sel.order_type(g, 10, u, null, null), T.OT_STOP, "mode 10 is Stop without a hover")
	eq(Sel.cursor_id(g, 11, u, h, g.cursor_2caa), Sel.CURSOR_TELEPORT, "cursor has no alive gate")
	eq(Sel.order_type(g, 15, u, null, null), 0, "modes past 14 give 0")
	eq(Sel.order_type(g, 0x101, u, null, g.cursor_2caa), T.OT_MOVE_GROUND, "mode uses its low byte")


func test_mode1_left() -> void:
	var g := new_game()
	var u := add(g, new_unit(1, 0, new_def(MOVE | ATK | GUARD), ALIVE | ARMED))
	eq(Sel.order_type(g, 1, u, null, g.cursor_2caa), T.OT_MOVE_GROUND, "ground unit on empty ground moves")
	eq(Sel.cursor_id(g, 1, u, null, g.cursor_2caa), Sel.CURSOR_MOVE, "move cursor")
	var own := add(g, new_unit(2, 0, new_def(MOVE), ALIVE | 0x20))
	eq(Sel.order_type(g, 1, u, own, g.cursor_2caa), 0, "own selectable unit: left click selects")
	eq(Sel.cursor_id(g, 1, u, own, g.cursor_2caa), Sel.CURSOR_SELECT, "select cursor")
	own.build_104 = 0.5
	eq(Sel.order_type(g, 1, u, own, g.cursor_2caa), T.OT_MOVE_GROUND, "own nanoframe is not selectable, non-builder moves")
	own.build_104 = 0.0
	var carrier := add(g, new_unit(3, 0, new_def(MOVE | LOAD)))
	own.transporter_86 = 3
	eq(Sel.order_type(g, 1, u, own, g.cursor_2caa), T.OT_MOVE_GROUND, "carried unit without carrier 0x40000000 is not selectable")
	carrier.f110 |= 0x40000000
	eq(Sel.order_type(g, 1, u, own, g.cursor_2caa), 0, "carrier exposing cargo keeps it selectable")
	var enemy := add(g, new_unit(4, 2, new_def(MOVE)))
	eq(Sel.order_type(g, 1, u, enemy, g.cursor_2caa), T.OT_ATTACK_CHASE, "enemy routes through mode 3")
	eq(Sel.cursor_id(g, 1, u, enemy, g.cursor_2caa), Sel.CURSOR_ATTACK, "attack cursor")
	var builder := add(g, new_unit(5, 0, new_def(MOVE | RECL | REP)))
	eq(Sel.order_type(g, 1, builder, enemy, g.cursor_2caa), T.OT_RECLAIM_UNIT, "unarmed reclaimer on enemy goes to mode 12")
	g.cells_14287[2 * 8 + 2][0] = 0   # feature 0 (flag 0x80) under the cursor (40, 40)
	eq(Sel.order_type(g, 1, builder, null, g.cursor_2caa), T.OT_RECLAIM, "visible feature: reclaim")
	eq(Sel.cursor_id(g, 1, builder, null, g.cursor_2caa), Sel.CURSOR_RECLAIM, "reclaim cursor")
	builder.def_92.f245 |= RES
	eq(Sel.order_type(g, 1, builder, null, g.cursor_2caa), T.OT_RESURRECT, "resurrect first")
	eq(Sel.cursor_id(g, 1, builder, null, g.cursor_2caa), Sel.CURSOR_RESURRECT, "resurrect cursor")
	eq(Sel.order_type(g, 1, builder, null, null), T.OT_MOVE_GROUND, "null pos skips the feature tests")
	var frame := add(g, new_unit(6, 1, new_def(MOVE)))
	frame.build_104 = 0.25
	frame.health_108 = 10
	eq(Sel.order_type(g, 1, builder, frame, g.cursor_2caa), T.OT_HELP_BUILD, "nanoframe of an ally: mode 8 help build")
	eq(Sel.cursor_id(g, 1, builder, frame, g.cursor_2caa), Sel.CURSOR_REPAIR, "repair cursor over a nanoframe")
	own.transporter_86 = 0
	own.health_108 = 10
	eq(Sel.order_type(g, 1, builder, own, g.cursor_2caa), 0, "damaged own finished unit still selects in the Left-Click interface")


func test_mode1_right() -> void:
	var g := new_game()
	g.interface_37efa = 1
	var builder := add(g, new_unit(1, 0, new_def(MOVE | GUARD | RECL | REP)))
	var own := add(g, new_unit(2, 0, new_def(MOVE), ALIVE | 0x20))
	eq(Sel.order_type(g, 1, builder, own, g.cursor_2caa), T.OT_FOLLOW_GROUND, "Right-Click: guard own full-health unit")
	eq(Sel.cursor_id(g, 1, builder, own, g.cursor_2caa), Sel.CURSOR_SELECT, "Right-Click cursor still shows select")
	own.health_108 = 40
	eq(Sel.order_type(g, 1, builder, own, g.cursor_2caa), T.OT_REPAIR_UNIT, "Right-Click: repair damaged own unit")
	own.build_104 = 0.5
	eq(Sel.order_type(g, 1, builder, own, g.cursor_2caa), T.OT_HELP_BUILD, "Right-Click: help build nanoframe")
	var enemy := add(g, new_unit(3, 2, new_def(MOVE)))
	eq(Sel.order_type(g, 1, builder, enemy, g.cursor_2caa), T.OT_RECLAIM_UNIT, "Right-Click: reclaim enemy directly")
	eq(Sel.cursor_id(g, 1, builder, enemy, g.cursor_2caa), Sel.CURSOR_RC_ENEMY, "Right-Click enemy cursor")
	var plane := add(g, new_unit(4, 0, new_def(MOVE | GUARD, FLY)))
	var base := add(g, new_unit(5, 1, new_def(0, 0x200)))
	eq(Sel.order_type(g, 1, plane, base, g.cursor_2caa), T.OT_VTOL_LANDING, "aircraft on allied airbase lands")
	eq(Sel.cursor_id(g, 1, plane, base, g.cursor_2caa), Sel.CURSOR_RC_FRIEND, "Right-Click friend cursor")
	var truck := add(g, new_unit(6, 0, new_def(MOVE | LOAD | GUARD)))
	eq(Sel.order_type(g, 1, truck, enemy, g.cursor_2caa), T.OT_GROUND_PICKUP, "transport picks up any loadable unit")
	g.interface_37efa = 2
	eq(Sel.order_type(g, 1, truck, enemy, g.cursor_2caa), T.OT_MOVE_GROUND, "interface 2 is not the Right-Click interface")


func test_mode2() -> void:
	var g := new_game()
	var plant := add(g, new_unit(1, 0, new_def(MOVE | PATROL), ALIVE, 0))
	eq(Sel.order_type(g, 2, plant, null, null), T.OT_QMOVE, "immobile canmove unit: QMove")
	eq(Sel.cursor_id(g, 2, plant, null, g.cursor_2caa), Sel.CURSOR_MOVE, "QMove shows the move cursor")
	var com := add(g, new_unit(2, 0, new_def(MOVE | ATK | GUARD | RECL | REP | CAPT | RES)))
	var enemy := add(g, new_unit(3, 2, new_def(MOVE)))
	eq(Sel.order_type(g, 2, com, enemy, g.cursor_2caa), T.OT_CAPTURE, "commander captures enemies in mode 2")
	eq(Sel.cursor_id(g, 2, com, enemy, g.cursor_2caa), Sel.CURSOR_CAPTURE, "capture cursor")
	g.cells_14287[2 * 8 + 2][0] = 0
	eq(Sel.cursor_id(g, 2, com, null, g.cursor_2caa), Sel.CURSOR_RESURRECT, "mode 2 cursor shows resurrect over a feature")
	eq(Sel.order_type(g, 2, com, null, g.cursor_2caa), T.OT_MOVE_GROUND, "but the order is still a move")
	var ally := add(g, new_unit(4, 1, new_def(MOVE)))
	ally.health_108 = 0xffff   # s16 -1 -> unsigned 0xffffffff is not below maxdamage
	eq(Sel.order_type(g, 2, com, ally, g.cursor_2caa), T.OT_FOLLOW_GROUND, "negative health word fails the unsigned repair test")


func test_mode3() -> void:
	var g := new_game()
	var tank := add(g, new_unit(1, 0, new_def(MOVE | ATK), ALIVE | ARMED))
	eq(Sel.order_type(g, 3, tank, null, g.cursor_2caa), T.OT_SUPPRESS, "attack ground")
	tank.weapons[0].flags_111 = 0x20000
	eq(Sel.order_type(g, 3, tank, null, g.cursor_2caa), 0, "anti-air weapon cannot attack ground")
	tank.weapons[0].flags_111 = 0
	var sub := add(g, new_unit(2, 2, new_def(MOVE)))
	g.sea_level_1427f = 40
	sub.y_6e = 10 * P   # 10 + maxy 10 < 40
	eq(Sel.order_type(g, 3, tank, sub, g.cursor_2caa), 0, "submerged target needs a water weapon")
	tank.slot1_3b = 2
	tank.weapons[1].flags_111 = 0x10000
	eq(Sel.order_type(g, 3, tank, sub, g.cursor_2caa), T.OT_ATTACK_CHASE, "slot 1 water weapon")
	sub.y_6e = 40 * P
	tank.def_92.f241 = 0x1000
	eq(Sel.order_type(g, 3, tank, sub, g.cursor_2caa), 0, "hovercraft with a water weapon cannot attack surface targets")
	g.sea_level_1427f = 0
	tank.def_92.f241 = 0
	var bomber := add(g, new_unit(3, 0, new_def(MOVE | ATK, FLY), ALIVE | ARMED))
	bomber.def_92.weapon1_1ee.flags_111 = 0x100
	eq(Sel.order_type(g, 3, bomber, null, g.cursor_2caa), T.OT_AIR_STRIKE, "bomber on ground")
	var fighter := add(g, new_unit(4, 2, new_def(MOVE, FLY)))
	eq(Sel.order_type(g, 3, bomber, fighter, g.cursor_2caa), 0, "bomber cannot attack aircraft")
	eq(Sel.cursor_id(g, 3, bomber, fighter, g.cursor_2caa), Sel.CURSOR_AIRSTRIKE, "bomber cursor")
	bomber.def_92.weapon1_1ee.flags_111 = 0
	eq(Sel.order_type(g, 3, bomber, fighter, g.cursor_2caa), T.OT_AIR_TO_AIR, "fighter on aircraft")
	bomber.def_92.f241 |= 0x8000000
	eq(Sel.order_type(g, 3, bomber, sub, g.cursor_2caa), T.OT_AIR_TO_GROUND_HOVER, "hoverattack gunship")
	var tower := add(g, new_unit(5, 0, new_def(ATK), ALIVE | ARMED | 0x20000000, 0))
	eq(Sel.order_type(g, 3, tower, sub, g.cursor_2caa), T.OT_ATTACK_NO_MOVE, "static defense")
	tower.f110 &= ~0x20000000
	eq(Sel.order_type(g, 3, tower, sub, g.cursor_2caa), 0, "immobile without 0x20000000 falls to the kamikaze test")
	var log := []
	var ru := func(u, t, slot): log.append(["u", t.id, slot]); return false
	var rp := func(u, pos, slot): log.append(["p", slot]); return true
	eq(Sel.cursor_id(g, 3, tower, sub, g.cursor_2caa, ru, rp), Sel.CURSOR_NO_ATTACK, "out of range target")
	eq(Sel.cursor_id(g, 3, tower, null, g.cursor_2caa, ru, rp), Sel.CURSOR_ATTACK, "ground in range")
	eq(log, [["u", 2, 0], ["p", 0]], "range callbacks")
	var bomb := add(g, new_unit(6, 0, new_def(MOVE, 0x10000000)))
	eq(Sel.order_type(g, 3, bomb, null, g.cursor_2caa), 0, "kamikaze needs canattack")
	bomb.def_92.f245 |= ATK
	eq(Sel.order_type(g, 3, bomb, sub, g.cursor_2caa), T.OT_ATTACK_KAMIKAZE, "unarmed kamikaze")


func test_other_modes() -> void:
	var g := new_game()
	var com := add(g, new_unit(1, 0, new_def(MOVE | ATK | GUARD | PATROL | RECL | REP | CAPT | DGUN)))
	com.def_92.buildlist_156 = 1
	com.weapons[2].energy_c0 = 500.0
	com.resources_ec.energy_8c = 499.5
	eq(Sel.order_type(g, 4, com, null, null), T.OT_ATTACK_SPECIAL, "mode 4 d-gun")
	eq(Sel.cursor_id(g, 4, com, null, g.cursor_2caa), Sel.CURSOR_NO_ATTACK, "not enough energy for slot 2")
	com.resources_ec.energy_8c = 500.0
	eq(Sel.cursor_id(g, 4, com, null, g.cursor_2caa), Sel.CURSOR_ATTACK, "equal energy is enough")
	eq(Sel.order_type(g, 9, com, null, null), T.OT_REPAIR_PATROL, "repairers patrol with RepairPatrol")
	eq(Sel.cursor_id(g, 9, com, null, g.cursor_2caa), Sel.CURSOR_PATROL, "patrol cursor")
	eq(Sel.order_type(g, 14, com, null, null), T.OT_MOBILE_BUILD, "mode 14 mobile build")
	var ally := add(g, new_unit(2, 1, new_def(MOVE, FLY)))
	eq(Sel.order_type(g, 7, com, ally, null), T.OT_FOLLOW_GROUND, "defend ally")
	eq(Sel.cursor_id(g, 7, com, ally, g.cursor_2caa), Sel.CURSOR_NORMAL, "ground guard cursor refuses aircraft")
	eq(Sel.order_type(g, 13, com, ally, null), T.OT_CAPTURE, "mode 13 captures any other player's unit, allied or not")
	var own := add(g, new_unit(3, 0, new_def(MOVE)))
	eq(Sel.order_type(g, 13, com, own, null), 0, "same player pointer")
	eq(Sel.order_type(g, 12, com, own, g.cursor_2caa), T.OT_RECLAIM_UNIT, "mode 12 reclaims own units")
	g.players[1].index_146 = 0   # same alliance index, different player record
	eq(Sel.order_type(g, 13, com, ally, null), T.OT_CAPTURE, "capture compares player records, not indices")
	eq(Sel.order_type(g, 5, com, null, null), 0, "mode 5 needs canload")
	var lifter := add(g, new_unit(4, 0, new_def(MOVE | LOAD, FLY)))
	var base := add(g, new_unit(5, 1, new_def(0, 0x200)))
	eq(Sel.order_type(g, 5, lifter, base, null), T.OT_VTOL_LANDING, "mode 5 with an airbase hover lands")
	eq(Sel.order_type(g, 5, lifter, null, null), T.OT_VTOL_UNLOAD, "mode 5 unload")
	eq(Sel.order_type(g, 6, lifter, own, null), T.OT_VTOL_PICKUP, "mode 6 pickup")
	eq(Sel.cursor_id(g, 6, lifter, own, g.cursor_2caa), Sel.CURSOR_AIR_LOAD, "air load cursor")
	own.health_108 = 30
	eq(Sel.order_type(g, 8, com, own, null), T.OT_REPAIR_UNIT, "mode 8 repair")


func test_predicates() -> void:
	var g := new_game()
	var rep := add(g, new_unit(1, 0, new_def(REP)))
	var t := add(g, new_unit(2, 0, new_def(0)))
	check(not Sel.can_repair(g, rep, t), "full health (equal) cannot be repaired")
	t.health_108 = 99
	check(Sel.can_repair(g, rep, t), "damaged unit")
	t.f110 |= 2
	check(not Sel.can_repair(g, rep, t), "airborne state 2")
	t.f110 &= ~3
	g.sea_level_1427f = 30
	t.y_6e = 15 * P   # top 25
	check(not Sel.can_repair(g, rep, t), "ground repairer: top below sea - depth")
	rep.def_92.depth_1be = 5
	check(Sel.can_repair(g, rep, t), "depth limit lowers the bar")
	rep.def_92.f241 = FLY
	check(not Sel.can_repair(g, rep, t), "aircraft need the top at or above sea level")
	rep.def_92.f241 = FLY | 0x200000
	check(Sel.can_repair(g, rep, t), "amphibious flag lifts the aircraft sea test")
	check(not Sel.can_repair(g, rep, null), "null target")
	var rec := add(g, new_unit(3, 0, new_def(RECL)))
	check(Sel.can_reclaim_unit(rec, t), "reclaim unit")
	t.def_92.f245 = CAPT
	check(not Sel.can_reclaim_unit(rec, t), "capturers cannot be reclaimed")
	var truck := add(g, new_unit(4, 0, new_def(LOAD)))
	var cargo := add(g, new_unit(5, 0, new_def(0)))
	truck.def_92.transport_capacity_22b = 1
	truck.cargo_8a = [5]
	cargo.transporter_86 = 3   # chain member claimed by another transport does not count
	g.sea_level_1427f = 0
	t.y_6e = 0
	t.def_92.f245 = 0
	check(Sel.can_load(g, truck, t), "chain member with another transporter is not counted")
	cargo.transporter_86 = 4
	check(not Sel.can_load(g, truck, t), "full transport")
	truck.def_92.transport_capacity_22b = 2
	t.def_92.footprintx_14a = 0xfffe
	check(Sel.can_load(g, truck, t), "negative footprint word fits")
	t.def_92.footprintx_14a = 5
	check(not Sel.can_load(g, truck, t), "footprint over transport size")
	t.def_92.footprintx_14a = 2
	t.def_92.minwaterdepth_1c0 = 0
	check(not Sel.can_load(g, truck, t), "ground transports need minwaterdepth < 0")
	truck.def_92.f241 = FLY
	check(Sel.can_load(g, truck, t), "air transports skip it")
	t.def_92.maxy_16e = 0
	check(not Sel.can_load(g, truck, t), "top must be strictly above sea level << 16")
	t.def_92.maxy_16e = 1
	t.build_104 = -0.0
	check(Sel.can_load(g, truck, t), "-0.0 build counts as finished")
	t.loco_0 = 0
	check(not Sel.can_load(g, truck, t), "immobile units cannot be loaded")


func test_feature_visible() -> void:
	var g := new_game()
	var u := add(g, new_unit(1, 0, new_def(RECL)))
	var pos := [40 * P, 0, 40 * P]
	g.cells_14287[2 * 8 + 2] = [0xfffe, 1, 1]    # back link to cell (1, 1)
	g.cells_14287[1 * 8 + 1] = [3, 0, 0]         # id 3 >= feature count 2: back links skip the count check
	check(Sel.feature_visible(g, u, pos), "back-linked occupant without count check")
	g.cells_14287[2 * 8 + 2] = [3, 0, 0]
	check(not Sel.feature_visible(g, u, pos), "direct occupant checks the count")
	g.cells_14287[2 * 8 + 2] = [0, 0, 0]
	g.viewing_player_2a43 = 3
	g.seen_14273[1 * 8 + 1] = 0x7   # square (1, 1) seen by viewers 0-2 only
	check(not Sel.feature_visible(g, u, pos), "viewing player's seen bit")
	g.viewing_player_2a43 = 18      # 1 << 18 misses the 16-bit word
	g.seen_14273[1 * 8 + 1] = 0xffff
	check(not Sel.feature_visible(g, u, pos), "shift count past the word")
	g.viewing_player_2a43 = 0
	pos[1] = 20 * P                 # lz = (40 - 10) >> 5 = 0
	g.seen_14273[1] = 0
	check(not Sel.feature_visible(g, u, pos), "seen row uses z - y/2")
	g.players[0].seen_w_80 = 1
	pos[1] = 0
	check(not Sel.feature_visible(g, u, pos), "seen bitmap width bound")


func test_aggregate() -> void:
	var g := new_game()
	g.players[0].units_last_6b = 3
	var a := add(g, new_unit(1, 0, new_def(MOVE | ATK), ALIVE | ARMED | 0x20))
	var b := add(g, new_unit(2, 0, new_def(PATROL), ALIVE | 0x20))
	var c := add(g, new_unit(3, 0, new_def(MOVE), ALIVE | 0x20))
	eq(Sel.aggregate_cursor(g, 1), Sel.CURSOR_NORMAL, "nothing selected, no hover")
	g.hover_2cba = 3
	eq(Sel.aggregate_cursor(g, 1), Sel.CURSOR_SELECT, "nothing selected over a selectable unit (mode 1)")
	eq(Sel.aggregate_cursor(g, 2), Sel.CURSOR_NORMAL, "other modes do not select")
	c.f110 = 0x20   # no alive test here
	eq(Sel.aggregate_cursor(g, 1), Sel.CURSOR_SELECT, "dead selectable hover still shows select")
	c.f110 = ALIVE | 0x20 | 0x10
	eq(Sel.aggregate_cursor(g, 1), Sel.CURSOR_SELECT, "the hovered unit is removed from the selection")
	a.f110 |= 0x10
	b.f110 |= 0x10
	g.mode_2cc3 = 9
	eq(Sel.aggregate_cursor(g, 9), Sel.CURSOR_PATROL, "minimum over the selection (patrol 7 < normal 0x13)")
	g.mode_2cc3 = 2
	eq(Sel.aggregate_cursor(g, 9), Sel.CURSOR_MOVE, "per-unit mode comes from the UI mode byte")


func test_group_issue() -> void:
	var g := new_game()
	g.players[0].units_last_6b = 4
	var queues := {}
	for id in range(1, 6):
		var u := add(g, new_unit(id, 0, new_def(MOVE | ATK | GUARD | 0x1), ALIVE | 0x10))
		u.x_6a = (id * 10) * P
		u.z_72 = 100 * P
		queues[id] = OrderQueue.new()
	g.units[4].f110 = ALIVE          # not selected
	g.units[5].f110 = ALIVE | 0x10   # selected but outside the local range
	var pos := [200 * P, 5 * P, 300 * P]
	var issued := Sel.group_issue(g, queues, 0, 0, T.OT_MOVE_GROUND, pos, 0, 0)
	eq(issued.map(func(e): return e[0]), [1, 2, 3], "recipients: selected units in the local range")
	# centre x = (10 + 20 + 30) / 3 = 20; offsets -10, 0, +10 (squared 100 <= 9000)
	eq([queues[1].main[0].x, queues[2].main[0].x, queues[3].main[0].x], [190 * P, 200 * P, 210 * P], "formation offsets")
	eq(queues[1].main[0].y, 5 * P, "y is taken from pos")
	check(queues[1].main[0].flags & T.R_ACKNOWLEDGE != 0, "non-shift issue acknowledges")
	g.units[3].x_6a = 200 * P        # offset 180 from centre 70: 32400 > 9000
	Sel.group_issue(g, queues, 0, 0, T.OT_MOVE_GROUND, pos, 0, 0)
	eq(queues[3].main[0].x, 200 * P, "units outside n*3000 get the plain position")
	eq(queues[3].main.size(), 1, "non-shift issue replaces the queue")
	Sel.group_issue(g, queues, 4, 0, T.OT_MOVE_GROUND, pos, 0, 0)
	eq(queues[3].main.size(), 0, "shift issue at the same spot toggles the order off")
	# boundary: two units, centre 77, offsets -77 / 77 + 30300/65536: hi32(dx*dx) == 6000 == n*3000
	g.units[3].f110 = ALIVE
	g.units[1].x_6a = 0
	g.units[2].x_6a = (154 << 16) + 30300
	g.units[1].z_72 = 0
	g.units[2].z_72 = 0
	Sel.group_issue(g, queues, 0, 0, T.OT_PATROL, pos, 0, 0)
	eq(queues[2].main[0].x, 200 * P + (77 << 16) + 30300, "offset exactly at the radius limit is kept")
	# mode 0 Standing_FireOrder needs firestandorders (0x2); Standing_MoveOrder needs 0x1
	g.units[3].f110 = ALIVE | 0x10
	g.units[2].def_92 = new_def(MOVE | 0x2)
	var fire := Sel.group_issue(g, queues, 0, 0, T.OT_STANDING_FIRE_ORDER, null, 1, 0)
	eq(fire.map(func(e): return e[0]), [2], "standing fire order only for firestandorders units")
	var hold := Sel.group_issue(g, queues, 0, 0, T.OT_STANDING_MOVE_ORDER, null, 1, 0)
	eq(hold.map(func(e): return e[0]), [1, 3], "standing move order only for mobilestandorders units")
	# hovered target: excluded from recipients and passed as the target for 0x200 types and for modes
	var enemy := add(g, new_unit(6, 2, new_def(MOVE)))
	g.hover_2cba = 1
	var attack := Sel.group_issue(g, queues, 0, 0, T.OT_ATTACK_CHASE, null, 0, 0)
	eq(attack.map(func(e): return e[0]), [2, 3], "hovered selected unit is excluded for 0x200 types")
	eq(queues[2].main[0].target, 1, "hover is the target")
	var moved := Sel.group_issue(g, queues, 0, 0, T.OT_MOVE_GROUND, pos, 0, 0)
	eq(moved.map(func(e): return e[0]), [1, 2, 3], "no exclusion for types without 0x200")
	g.hover_2cba = 6
	var modal := Sel.group_issue(g, queues, 0, 3, 0, g.cursor_2caa, 0, 0)
	eq(modal, [], "mode 3 on unarmed units issues nothing")
	g.units[2].f110 |= ARMED
	g.units[2].def_92.f245 |= ATK
	var shots := Sel.group_issue(g, queues, 0, 3, 0x7700, g.cursor_2caa, 0, 0)
	eq(shots.map(func(e): return [e[0], e[1]]), [[2, T.OT_ATTACK_CHASE]], "mode 3 per-unit type (type argument high bytes ignored)")
	eq(queues[2].main[0].target, 6, "mode issues target the hover")
	g.units[1].def_92.f245 |= 0x100
	g.units[1].def_92.f241 = FLY
	var unload := Sel.group_issue(g, queues, 0, 5, 0, pos, 0, 0)
	eq(unload.map(func(e): return [e[0], e[1]]), [[1, T.OT_VTOL_UNLOAD]], "mode 5 sees no hover (no landing, hover not excluded)")
	g.hover_2cba = 0
	for id in [1, 2, 3]:
		g.units[id].f110 &= ~0x10
	eq(Sel.group_issue(g, queues, 0, 0, T.OT_STOP, null, 0, 0), [], "empty selection issues nothing")


func test_acknowledge() -> void:
	var g := new_game()
	var u := add(g, new_unit(1, 0, new_def(MOVE)))
	var q := OrderQueue.new()
	var order: Dictionary = q.issue(T.OT_MOVE_GROUND, false, 0, [0, 0, 0], 0, 0)
	eq(Sel.acknowledge(g, u, order, null), [1, 5, null], "first handler run replies")
	eq(Sel.acknowledge(g, u, order, null), [], "only once")
	var shifted: Dictionary = q.issue(T.OT_MOVE_GROUND, true, 0, [64 * P, 0, 0], 0, 0)
	eq(Sel.acknowledge(g, u, shifted, "ok"), [], "shift issues never acknowledge")
	var other: Dictionary = q.issue(T.OT_STOP, false, 0, null, 0, 0)
	g.viewing_player_2a43 = 1
	eq(Sel.acknowledge(g, u, other, "ok"), [], "units of other players stay silent")
	check(other.flags & T.R_ACKNOWLEDGE == 0, "the flag is cleared even without a reply")
	other = q.issue(T.OT_STOP, false, 0, null, 0, 0)
	g.viewing_player_2a43 = 0
	u.f110 |= 0x4000
	eq(Sel.acknowledge(g, u, other, "ok"), [], "f110 0x4000 silences replies")
	other = q.issue(T.OT_STOP, false, 0, null, 0, 0)
	u.f110 = ALIVE
	eq(Sel.acknowledge(g, u, other, "ok"), [1, 5, "ok"], "explicit sound")
