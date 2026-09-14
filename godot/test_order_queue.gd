extends SceneTree
## Hand-built order queue scenarios (expected values read from the disassembly of 0x43a0c0, 0x43adc0, 0x43afc0,
## 0x43b7c0, 0x43bad0, 0x439eb0 and 0x43b0b0). The randomized native comparison is compare_native_order_queue.gd.
const OrderTable = preload("res://order_table.gd")
const OrderQueue = preload("res://order_queue.gd")

const T := OrderTable
const P := 0x10000   # one world unit in 16.16

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func types(list: Array) -> Array:
	return list.map(func(o): return o.type)


func new_queue(codes: Array = []) -> OrderQueue:
	var q := OrderQueue.new()
	var state := {codes = codes, log = []}
	q.set_meta("state", state)
	q.rand = func(n): return n - 1
	q.handler = func(order, ev, background):
		state.log.append([order.type, ev, background])
		return state.codes.pop_front() if not state.codes.is_empty() else 3
	q.target_alive = func(id): return id != 99
	return q


func _initialize() -> void:
	test_table()
	test_constructor()
	test_insert_modes()
	test_marker_and_patrol_return()
	test_idle_strip()
	test_toggle()
	test_dispatch_codes()
	test_background()
	test_idle_creation()
	test_factory_counts()
	print("ORDER_QUEUE %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func test_table() -> void:
	check(T.count() == 67, "67 order types")
	check(T.name(T.OT_MOVE_GROUND) == "Move_Ground" and T.OT_MOVE_GROUND == 0x19, "Move_Ground is 0x19")
	check(T.OT_ATTACK_CHASE == 0x05 and T.OT_ATTACK_KAMIKAZE == 0x06, "'_' sorts before letters (Attack_Chase < AttackSpecial)")
	check(T.flags(T.OT_SELF_DESTRUCT) == 0x40040 and T.flags(T.OT_STANDING_FIRE_ORDER) == 0x10060, "SelfDestruct / Standing_FireOrder flags")
	check(T.handler_id(T.OT_QMOVE) == T.handler_id(T.OT_QPATROL), "QMove and QPatrol share handler 0x403160")
	check(T.find("Stop") == 0x2c and T.find("stop") == -1, "exact name lookup")


func test_constructor() -> void:
	var q := new_queue()
	q.tick = 77
	var a := q.make_order(T.OT_ATTACK_CHASE, 0, [1, 2, 3], 4, 5, 6)
	check(a.flags == 0x80 and a.target == 0, "no target strips 0x200")
	var b := q.make_order(T.OT_ATTACK_CHASE, 99, null, 0, 0, 0)
	check(b.flags == 0x280 and b.target == 0, "dead target keeps 0x200 but stores no reference")
	var c := q.make_order(T.OT_MOVE_GROUND, 5, null, 0, 0, 0)
	check(c.flags == 0x2 and c.target == 0 and [c.x, c.y, c.z] == [0, 0, 0], "no position strips 0x400; type without 0x200 drops the target")
	check(c.wake == 0xffffffff and c.tick == 77 and a.p3e == 6, "wake -1, creation tick, p3e")


func test_insert_modes() -> void:
	var q := new_queue()
	var cleared := []
	q.on_destroy = func(o): cleared.append([o.type, o.flags & T.R_SKIP_WEAPON_CLEAR])
	q.insert(T.OT_MOVE_GROUND, false, 0, [P, 0, P], 0, 0)
	q.insert(T.OT_WAIT, true, 0, null, 0, 0)            # 0x4 protected
	q.insert(T.OT_PATROL, true, 0, [2 * P, 0, P], 0, 0)
	var move: Dictionary = q.insert(T.OT_MOVE_GROUND, false, 0, [3 * P, 0, P], 0, 0)
	check(types(q.main) == [T.OT_WAIT, T.OT_MOVE_GROUND], "replace keeps 0x4 orders")
	check(cleared == [[T.OT_MOVE_GROUND, 0], [T.OT_PATROL, 0x10000]], "only the entry head skips 0x10000")
	check(move.flags == 0x402 | 0x2001 | 0x1000, "non-shift issue flags 0x2001 plus marker")
	var shifted: Dictionary = q.insert(T.OT_PATROL, true, 0, [4 * P, 0, P], 0, 0)
	check(shifted.flags & 0x2000 == 0 and shifted.flags & 1, "shift issue has no acknowledgement bit")
	var stance: Dictionary = q.insert(T.OT_STANDING_FIRE_ORDER, false, 0, null, 2, 0)
	check(q.main[0].id == stance.id and q.main.size() == 4, "0x60 order goes to the head without clearing")
	var sd: Dictionary = q.insert(T.OT_SELF_DESTRUCT, false, 0, null, 0, 0)
	check(q.bg.size() == 1 and q.bg[0].id == sd.id and q.main.size() == 4, "0x40000 order goes to the background list")


func test_marker_and_patrol_return() -> void:
	var q := new_queue()
	q.unit_pos = [7 * P, 0, 7 * P]
	var p1: Dictionary = q.insert(T.OT_PATROL, false, 0, [P, 0, P], 0, 0)
	q.patrol_append(p1)   # handler state 0: origin appended raw, no marker
	check(types(q.main) == [T.OT_PATROL, T.OT_PATROL] and q.main[1].x == 7 * P and q.main[1].flags == 0x412, "origin appended at tail")
	var p2: Dictionary = q.insert(T.OT_PATROL, true, 0, [2 * P, 0, P], 0, 0)
	check(q.main[1].id == p2.id and q.main[2].x == 7 * P, "shift patrol lands before the auto return point")
	check(p1.flags & T.R_MARKER == 0 and p2.flags & T.R_MARKER, "marker moves to the newest player order")
	q.patrol_append(p2)
	check(q.main.size() == 3 and p2.flags & T.R_PATROL_ORIGIN, "second origin skipped once 0x8000 is present")


func test_idle_strip() -> void:
	var q := new_queue()
	q.controller = 1
	q.default_mission = T.OT_STANDBY
	q.dispatch()
	check(types(q.main) == [T.OT_STANDBY] and q.main[0].flags == 0x24000, "idle Standby created with 0x4000")
	var inherited := q.make_order(T.OT_ATTACK_CHASE, 3, null, 0, 0, 0)
	q.push_front_inherit(inherited)
	check(inherited.flags & T.R_IDLE, "engage insert inherits 0x4000")
	var skipped := []
	q.on_destroy = func(o): skipped.append(o.flags & T.R_SKIP_WEAPON_CLEAR)
	q.insert(T.OT_MOVE_GROUND, true, 0, [P, 0, P], 0, 0)
	check(types(q.main) == [T.OT_MOVE_GROUND] and skipped == [0, 0], "shift issue strips all head idle orders without 0x10000")


func test_toggle() -> void:
	var q := new_queue()
	q.insert(T.OT_MOVE_GROUND, false, 0, [10 * P, 5 * P, 10 * P], 1, 0)
	check(q.issue(T.OT_MOVE_GROUND, true, 0, [10 * P + 0x100001, 0, 10 * P], 9, 0) != null, "0x100001 away adds")
	check(q.main.size() == 2, "two waypoints")
	check(q.issue(T.OT_MOVE_GROUND, true, 0, [10 * P - 0x100000, 0, 10 * P + 0x100000], 9, 0) == null, "exactly 0x100000 toggles (y, p36 ignored)")
	check(q.main.size() == 1 and q.main[0].x == 10 * P + 0x100001, "first match removed")
	var r := new_queue()
	r.insert(T.OT_MOVE_GROUND, false, 0, [0x7ff80000, 0, 0], 0, 0)
	check(r.issue(T.OT_MOVE_GROUND, true, 0, [-0x7ff80000, 0, 0], 0, 0) == null and r.main.is_empty(), "32-bit wrap counts as near")
	var s := new_queue()
	s.insert(T.OT_WAIT, false, 0, null, 0, 0)
	check(s.issue(T.OT_WAIT, true, 0, [0xf0000, 0, -0xf0000], 0, 0) == null, "position-less order compares at the origin")
	s.insert(T.OT_SELF_DESTRUCT, false, 0, null, 0, 0)
	s.issue(T.OT_SELF_DESTRUCT, true, 0, null, 0, 0)
	check(s.bg.size() == 2, "background orders are never toggled (main list only)")


func test_dispatch_codes() -> void:
	var q := new_queue([1, 2])
	var move: Dictionary = q.insert(T.OT_MOVE_GROUND, false, 0, [P, 0, P], 0, 0)
	move.mask = 0
	# Handler must re-arm: code 1 with mask 0 is re-run in the same tick; code 2 without a mask would loop, so arm it.
	q.handler = func(order, ev, background):
		var state: Dictionary = q.get_meta("state")
		state.log.append([order.type, ev])
		var code: int = state.codes.pop_front() if not state.codes.is_empty() else 3
		if code == 2:
			order.mask = 0x20
		return code
	q.dispatch()
	check(move.state == 1 and move.mask == 0x20 and q.get_meta("state").log.size() == 2, "code 1 loops in the same tick, code 2 waits")
	q.unit_ev = 0x8021
	q.handler = func(order, ev, background): return 5
	var cleared := []
	q.clear_weapon_targets = func(mode): cleared.append(mode)
	q.dispatch()
	check(q.unit_ev == 0x8001 and q.main.is_empty() and cleared == [3], "event consumed; code 5 removes the head with a weapon clear")

	var w := new_queue()
	w.tick = 100
	var a: Dictionary = w.insert(T.OT_MOVE_GROUND, false, 0, [P, 0, P], 0, 0)
	w.insert(T.OT_PATROL, true, 0, [2 * P, 0, P], 0, 0)
	w.handler = func(order, ev, background): return 9
	w.dispatch()
	check(w.main.size() == 1 and a.flags & T.R_CODE9 and w.main[0].type == T.OT_PATROL, "code 9 with a successor removes")
	var last: Dictionary = w.main[0]
	check(last.state == 0 and last.mask == 1 and last.wake == 100 + 29 + 30, "same tick: code 9 on the new tail arms rand(30)+30")
	w.tick = 159
	w.handler = func(order, ev, background): return 3
	w.dispatch()
	check(last.wake == 159 + 14 + 30, "wake passed -> pending timer event, code 3 re-arms rand(15)+30")

	var r := new_queue()
	var first: Dictionary = r.insert(T.OT_MOVE_GROUND, false, 0, [P, 0, P], 0, 0)
	r.insert(T.OT_PATROL, true, 0, [2 * P, 0, P], 0, 0)
	r.handler = func(order, ev, background):
		order.mask = 1
		return 6 if order.id == first.id else 2
	r.dispatch()
	check(r.main[1].id == first.id, "code 6 rotates the head to the tail")
	var skip := []
	r.on_destroy = func(o): skip.append(o.flags & T.R_SKIP_WEAPON_CLEAR)
	r.insert(T.OT_SELF_DESTRUCT, false, 0, null, 0, 0)
	r.main[0].mask = 0
	r.handler = func(order, ev, background): return 7
	r.dispatch()
	check(r.main.is_empty() and r.bg.is_empty() and skip == [0, 0x10000, 0x10000], "code 7 wipes main then background")


func test_background() -> void:
	var q := new_queue()
	q.tick = 10
	var sd: Dictionary = q.insert(T.OT_SELF_DESTRUCT, false, 0, null, 0, 0)
	var calls := []
	q.handler = func(order, ev, background):
		calls.append([order.state, ev, background])
		return 1 if calls.size() < 3 else 3
	q.dispatch_bg()
	check(calls == [[0, 0, true], [1, 0, true], [2, 0, true]] and sd.mask == 1 and sd.wake == 10 + 14 + 30, "restart at head until armed")
	q.tick = sd.wake
	var skip := []
	q.on_destroy = func(o): skip.append(o.flags & T.R_SKIP_WEAPON_CLEAR)
	q.handler = func(order, ev, background): return 9
	q.dispatch_bg()
	check(q.bg.is_empty() and sd.wake == 54 and skip == [0x10000], "background code 9 removes, always 0x10000")


func test_idle_creation() -> void:
	var q := new_queue()
	q.controller = 3
	q.default_mission = T.OT_STANDBY
	q.dispatch()
	check(q.main.is_empty(), "no idle order for controller 3")
	q.controller = 2
	q.player_valid = false
	q.dispatch()
	check(q.main.is_empty(), "no idle order without a player")
	q.player_valid = true
	q.default_mission = T.OT_SELF_DESTRUCT
	q.dispatch()
	check(q.bg.size() == 1 and q.bg[0].flags == 0x44040, "background default mission goes to bg")


func test_factory_counts() -> void:
	var q := new_queue()
	q.factory_count(T.OT_BUILDING_BUILD, 7, 2)
	q.factory_count(T.OT_BUILDING_BUILD, 7, 3)
	check(q.main.size() == 1 and q.main[0].p3a == 5 and q.count_builds(7) == 5, "positive count merges into the tail")
	q.factory_count(T.OT_BUILDING_BUILD, 8, 1)
	q.factory_count(T.OT_BUILDING_BUILD, 7, 1)
	check(q.main.size() == 3 and q.count_builds(7) == 6, "non-tail match appends a new order")
	q.factory_count(T.OT_BUILDING_BUILD, 7, -2)
	check(q.main.size() == 2 and q.count_builds(7) == 4, "negative count removes the last match (p3a 1 <= 2) then subtracts the rest")
	q.factory_count(T.OT_BUILDING_BUILD, 7, -100)
	check(q.main.size() == 1 and q.count_builds(7) == 0 and q.find(T.OT_BUILDING_BUILD).p36 == 8, "large negative removes all")
