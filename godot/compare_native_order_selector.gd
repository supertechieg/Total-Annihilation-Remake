extends SceneTree
## Compare order_selector.gd with the ORIGINAL 0x43f0e0, 0x43e490, 0x4899b0/0x489960/0x489a90, 0x48d220, 0x48cf30 and
## 0x438880 run by tools/native_order_selector.py (local/orders/native-order-selector.json).
const OrderQueue = preload("res://order_queue.gd")
const Sel = preload("res://order_selector.gd")

const FLOAT_KEYS := ["build_104", "energy_8c", "metal_98", "energy_c0", "metal_c4"]

var checks := 0
var failures := 0
var default_sound := ""


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 15:
			printerr(message)


static func norm(value, key := ""):
	if value is Array:
		return value.map(func(v): return norm(v))
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = norm(value[k], k)
		return out
	if value is String and value == "NaN" and key in FLOAT_KEYS:
		return NAN
	if value is float and not key in FLOAT_KEYS:
		return int(value)
	return value


func _initialize() -> void:
	var path := ProjectSettings.globalize_path("res://../local/orders/native-order-selector.json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		printerr("Run tools/native_order_selector.py first")
		quit(1)
		return
	default_sound = data.default_reply_sound
	var selects := 0
	var groups := 0
	for case: Dictionary in data.cases:
		if case.kind == "select":
			run_select(case)
			selects += 1
		else:
			run_group(case)
			groups += 1
	print("ORDER_SELECTOR_NATIVE %d / %d checks match (%d select cases, %d group cases)" % [checks - failures, checks, selects, groups])
	quit(0 if failures == 0 and checks > 0 else 1)


func range_callables(events: Array, answers: Dictionary) -> Array:
	var ru := func(u, t, slot):
		events.append(["range_unit", u.id, t.id, slot])
		return int(answers.get(str(u.id), [0, 0])[0]) != 0
	var rp := func(u, pos, slot):
		events.append(["range_pos", u.id, pos.duplicate(), slot])
		return int(answers.get(str(u.id), [0, 0])[1]) != 0
	return [ru, rp]


func run_select(case: Dictionary) -> void:
	var g: Dictionary = norm(case.g)
	var label := "case %d mode %d" % [int(case.index), int(case.mode)]
	var u: Dictionary = g.units[int(case.unit)]
	var h = Sel.unit(g, int(case.hover))
	var pos = null if case.pos_null else g.cursor_2caa
	var order := Sel.order_type(g, int(case.mode), u, h, pos)
	check(order == int(case.order), "%s order expected %d got %d" % [label, int(case.order), order])
	# 0x43f0e0 calls no stubbed boundary (range tests, allocator, reply queue): its native event log must be empty
	check(case.order_events.is_empty(), "%s 0x43f0e0 native events %s" % [label, case.order_events])
	var events := []
	var r := range_callables(events, norm(case.range))
	var cursor := Sel.cursor_id(g, int(case.mode), u, h, g.cursor_2caa, r[0], r[1])
	check(cursor == int(case.cursor), "%s cursor expected %d got %d" % [label, int(case.cursor), cursor])
	check(events == norm(case.cursor_events), "%s cursor range calls expected %s got %s" % [label, case.cursor_events, events])
	for key: String in case.predicates:
		var parts := key.split(",")
		var a: Dictionary = g.units[int(parts[0])]
		var b = Sel.unit(g, int(parts[1]))
		var expected: Array = case.predicates[key]
		var got := [1 if Sel.can_repair(g, a, b) else 0,
			(1 if Sel.can_reclaim_unit(a, b) else 0) if b != null else null,
			(1 if Sel.can_load(g, a, b) else 0) if b != null else null]
		check(got == norm(expected), "%s predicates %s expected %s got %s" % [label, key, expected, got])


func dump_queue(q, uid: int) -> Array:
	var lists := []
	for list in [q.main, q.bg]:
		lists.append(list.map(func(o):
			var row: Array = OrderQueue.dump_order(o)
			row[5] = uid if o.owner else 0
			return row))
	return lists


func run_group(case: Dictionary) -> void:
	var g: Dictionary = norm(case.g)
	var events := []
	var queues := {}
	var all_ids := []
	for u in g.units:
		if u == null:
			continue
		var uid: int = u.id
		all_ids.append(uid)
		var q := OrderQueue.new()
		q.tick = g.tick
		q.target_alive = func(id): return Sel.unit(g, id) != null and Sel.unit(g, id).alive_a6 != 0
		q.on_destroy = func(order): events.append(["destroy", order.id, order.flags])
		q.on_free = func(order): events.append(["free", order.id])
		q.clear_weapon_targets = func(m): events.append(["clear_weapons", uid, m])
		q.stop_building = func(order): events.append(["stop_building", order.id])
		q.destroy_notify = func(order): events.append(["destroy_cb", order.id])
		queues[uid] = q
	var ids := {next = 1}
	var step := 0
	for op: Dictionary in case.ops:
		events.clear()
		var label := "case %d op %d %s" % [int(case.index), step, op.op]
		match op.op:
			"group":
				var observer := func(uid, t, shift, target, at, p5, p6):
					events.append(["issue", uid, t, shift, target, at.duplicate() if at != null else null, p5, p6])
				Sel.group_issue(g, queues, int(op.input_flags), int(op.mode), int(op.type), norm(op.pos), int(op.p5), int(op.p6), ids, observer)
			"cursor":
				g.mode_2cc3 = int(op.mode) if op.ui_mode == null else int(op.ui_mode)
				var r := range_callables(events, norm(op.range))
				var result := Sel.aggregate_cursor(g, int(op.mode), r[0], r[1])
				check(result == int(op.result), "%s aggregate cursor expected %d got %d" % [label, int(op.result), result])
			"ack":
				var i := 0
				var args: Array = norm(op.args)
				for uid in all_ids:
					var q = queues[uid]
					for order in q.main + q.bg:
						var arg: int = args[i % args.size()]
						i += 1
						var reply := Sel.acknowledge(g, g.units[uid], order, "custom-reply" if arg else null)
						if not reply.is_empty():
							events.append(["reply", reply[0], reply[1], reply[2] if reply[2] != null else default_sound])
			"select":
				for flip in norm(op.flips):
					g.units[flip[0]].f110 ^= flip[1]
			"hover":
				g.hover_2cba = int(op.id)
			"cursor_pos":
				g.cursor_2caa = norm(op.pos)
			"insert":
				var q = queues[int(op.unit)]
				q.next_id = ids.next
				q.insert(int(op.type), int(op.shift) != 0, int(op.target), norm(op.pos), int(op.p36), int(op.p3a))
				ids.next = q.next_id
				if not q.main.is_empty():
					q.main[0].flags |= int(op.flags_or)
			_:
				check(false, label + " unknown op")
		check(events == norm(op.events), "%s events\n expected %s\n got      %s" % [label, op.events, events])
		for uid in all_ids:
			var got := dump_queue(queues[uid], uid)
			var expected = norm(op.queues.get(str(uid), [[], []]))
			check(got == expected, "%s unit %d queues\n expected %s\n got      %s" % [label, uid, expected, got])
		check(ids.next == int(op.next_id), "%s next id expected %d got %d" % [label, int(op.next_id), ids.next])
		step += 1
	for q in queues.values():
		for key in ["target_alive", "on_destroy", "on_free", "clear_weapon_targets", "stop_building", "destroy_notify"]:
			q.set(key, Callable())
