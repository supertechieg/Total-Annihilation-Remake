extends SceneTree
## Compare order_table.gd and order_queue.gd with the ORIGINAL 0x43bc90 table build, 0x43adc0, 0x43afc0, 0x43b7c0, 0x43bad0
## and list helpers run by tools/native_order_queue.py (local/orders/*.json).
const OrderTable = preload("res://order_table.gd")
const OrderQueue = preload("res://order_queue.gd")

const DEAD_TARGET := 6

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 12:
			printerr(message)


static func norm(value):
	if value is Array:
		return value.map(func(v): return norm(v))
	if value is float:
		return int(value)
	return value


func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://../local/orders/")
	var table = JSON.parse_string(FileAccess.get_file_as_string(root + "order-table.json"))
	var data = JSON.parse_string(FileAccess.get_file_as_string(root + "native-order-queue.json"))
	if not table is Dictionary or not data is Dictionary:
		printerr("Run tools/native_order_queue.py first")
		quit(1)
		return
	check(OrderTable.count() == table.entries.size(), "table size %d vs %d" % [OrderTable.count(), table.entries.size()])
	for entry: Dictionary in table.entries:
		var i := int(entry.id)
		var expected := [entry.name, int(entry.flags), int(entry.draw_mask), int(entry.icon), int(entry.handler), int(entry.draw)]
		check(i < OrderTable.count() and norm(OrderTable.TYPES[i]) == expected, "table %d expected %s got %s" % [i, expected, OrderTable.TYPES[i] if i < OrderTable.count() else null])
	for sequence: Dictionary in data.sequences:
		run_sequence(sequence)
	print("ORDER_QUEUE_NATIVE %d / %d checks match" % [checks - failures, checks])
	quit(0 if failures == 0 and checks > 0 else 1)


func find_order(q, id: int):
	for list in [q.main, q.bg]:
		for order in list:
			if order.id == id:
				return order
	return null


func run_sequence(sequence: Dictionary) -> void:
	var setup: Dictionary = sequence.setup
	var q = OrderQueue.new()
	q.tick = int(setup.tick)
	q.player_valid = int(setup.player_valid) != 0
	q.controller = int(setup.controller)
	q.default_mission = int(setup.default_mission)
	q.unit_pos = norm(setup.unit_pos)
	var ctx := {events = [], actions = [], ai = 0, native_events = [], ri = 0}
	q.target_alive = func(id): return id != DEAD_TARGET
	q.on_destroy = func(order): ctx.events.append(["destroy", order.id, order.flags])
	q.destroy_notify = func(order): ctx.events.append(["destroy_cb", order.id, "unit", 2])
	q.stop_building = func(order): ctx.events.append(["stop_building", order.id])
	q.clear_weapon_targets = func(mode): ctx.events.append(["clear_weapons", "unit", mode])
	q.aim_reset = func(slot): ctx.events.append(["aim_reset", "unit", slot])
	q.on_free = func(order): ctx.events.append(["free", order.id])
	q.rand = func(n):
		var result := 0
		while ctx.ri < ctx.native_events.size():
			var e: Array = ctx.native_events[ctx.ri]
			ctx.ri += 1
			if e[0] == "rand":
				result = int(e[2])
				break
		ctx.events.append(["rand", n, result])
		return result
	q.handler = func(order, ev, background):
		ctx.events.append(["call", "bg" if background else "main", order.id, "unit", order.type, order.state, ev, order.pending, order.wake, order.flags])
		if ctx.ai >= ctx.actions.size():
			return 3
		var a: Dictionary = ctx.actions[ctx.ai]
		ctx.ai += 1
		order.mask |= int(a.mask_or)
		order.pending |= int(a.pending_or)
		order.flags |= int(a.flags_or)
		if a.wake != null:
			order.wake = (q.tick + int(a.wake)) & OrderQueue.MASK32
		if a.push != null:
			var p: Dictionary = a.push
			var pushed = q.make_order(int(p.type), int(p.target), norm(p.pos), int(p.p36), int(p.p3a), 0)
			q.push_front_inherit(pushed)
		return int(a.code)
	var index := int(sequence.index)
	var step := 0
	for op: Dictionary in sequence.ops:
		ctx.events = []
		ctx.actions = op.actions
		ctx.ai = 0
		ctx.native_events = op.events
		ctx.ri = 0
		var result = null
		var label := "seq %d op %d %s" % [index, step, op.op]
		match op.op:
			"insert":
				q.insert(int(op.type), int(op.shift) != 0, int(op.target), norm(op.pos), int(op.p36), int(op.p3a))
			"issue":
				q.issue(int(op.type), int(op.shift) != 0, int(op.target), norm(op.pos), int(op.p36), int(op.p3a))
			"dispatch":
				q.tick = (q.tick + int(op.advance)) & OrderQueue.MASK32
				q.dispatch()
			"dispatch_bg":
				q.tick = (q.tick + int(op.advance)) & OrderQueue.MASK32
				q.dispatch_bg()
			"post_order":
				var order = find_order(q, int(op.id))
				check(order != null, label + " missing order")
				if order != null:
					order.pending |= int(op.bits)
			"post_unit":
				q.unit_ev = (q.unit_ev | int(op.bits)) & 0xffff
			"remove", "rotate", "patrol_append":
				var order = find_order(q, int(op.id))
				check(order != null, label + " missing order")
				if order != null:
					if op.op == "remove":
						q.remove(order)
					elif op.op == "rotate":
						q.rotate_to_tail(order)
					else:
						q.patrol_append(order)
			"clear":
				q.clear_all(int(op.include_bg) != 0)
			"factory":
				q.factory_count(int(op.type), int(op.p36), int(op.count))
			"find":
				var found = q.find(int(op.type))
				result = found.id if found != null else 0
			"count":
				result = q.count_builds(int(op.p36))
			"push_front_inherit", "append", "marker_insert":
				var s: Dictionary = op.spec
				var order = q.make_order(int(s.type), int(s.target), norm(s.pos), int(s.p36), int(s.p3a), int(s.p3e))
				if op.op == "push_front_inherit":
					q.push_front_inherit(order)
				elif op.op == "append":
					q.append(order)
				else:
					q.marker_insert(order)
			_:
				check(false, label + " unknown op")
		var expected_events = norm(op.events)
		check(ctx.events == expected_events, "%s events\n expected %s\n got      %s" % [label, expected_events, ctx.events])
		check(ctx.ai == op.actions.size(), "%s used %d of %d scripted actions" % [label, ctx.ai, op.actions.size()])
		var expected_main = norm(op.main)
		var got_main = q.dump(q.main)
		check(got_main == expected_main, "%s main\n expected %s\n got      %s" % [label, expected_main, got_main])
		var expected_bg = norm(op.bg)
		var got_bg = q.dump(q.bg)
		check(got_bg == expected_bg, "%s bg\n expected %s\n got      %s" % [label, expected_bg, got_bg])
		check(q.unit_ev == int(op.unit_ev) and q.tick == int(op.tick), "%s unit_ev/tick expected %d/%d got %d/%d" % [label, int(op.unit_ev), int(op.tick), q.unit_ev, q.tick])
		if op.result != null:
			check(result == int(op.result), "%s result expected %s got %s" % [label, op.result, result])
		var refs := [0, 0, 0, 0, 0, 0]
		for list in [q.main, q.bg]:
			for order in list:
				if order.target > 0:
					refs[order.target - 1] += 1
		check(refs == norm(op.target_refs), "%s target refs expected %s got %s" % [label, op.target_refs, refs])
		step += 1
	# Break the queue <-> lambda reference cycle.
	for key in ["handler", "destroy_notify", "on_destroy", "stop_building", "clear_weapon_targets", "aim_reset", "on_free", "rand", "target_alive"]:
		q.set(key, Callable())
