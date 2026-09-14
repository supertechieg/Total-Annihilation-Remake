extends RefCounted
## Per-unit order queue core: TotalA.exe order record 0x43a0c0, insert 0x43adc0, shift toggle 0x43afc0, main dispatcher
## 0x43b7c0, background dispatcher 0x43bad0 and the list helpers around them (0x439d80..0x43b0b0).
## Data model only: order handlers, weapons, building scripts, goals and RNG are injected callables.
## Native evidence: tools/native_order_queue.py + godot/compare_native_order_queue.gd (see analysis/ORDER_QUEUE.md).
##
## Linked lists become Arrays (index 0 = head). Every "removed while not head" test compares against the head the native
## routine read, which is not always the live head (documented per routine).
const OrderTable = preload("res://order_table.gd")

const MASK32 := 0xffffffff
const TOGGLE_HALF_WIDTH := 0x100000   # 0x43afc0: |dx| and |dz| <= 16.0 world units (16.16 fixed)
const NO_WAKE := 0xffffffff

## Order record, one Dictionary per native 0x56-byte record:
## id (port-only allocation serial), type +4 (byte), state +5 (byte), mask +6, wake +0xA, owner +0xE (bool: queued on this
## unit), target +0x16 (unit id, 0 none), x/y/z +0x22/+0x26/+0x2A (16.16), leash +0x2E, last_seen +0x32, p36 +0x36,
## p3a +0x3A, p3e +0x3E, flags +0x42, tick +0x46, pending +0x4E, goal +0x52. Next pointer +0x4A is the Array order.
var main: Array = []        # unit+0x5C
var bg: Array = []          # unit+0x60
var unit_ev := 0            # word unit+0xBA
var tick := 0               # game+0x38A47 (u32)
var next_id := 1
var unit_pos := [0, 0, 0]   # unit+0x6A (Patrol origin append)
var player_valid := true    # [unit+0x96] != 0
var controller := 0         # player+0x73 (idle orders only for 1 and 2)
var default_mission := 0    # unitdef+0x230

var handler := Callable()             # (order: Dictionary, ev: int, background: bool) -> int return code
var destroy_notify := Callable()      # (order) handler call with ev 2 when mask & 2 (0x43a21a)
var on_destroy := Callable()          # (order) observer at 0x43a1f0 entry
var stop_building := Callable()       # (order) COB StopBuilding when flag 0x400000
var cancel_goal := Callable()         # (order) goal +0x52 release
var clear_weapon_targets := Callable()  # (mode) 0x489800(unit, 3)
var aim_reset := Callable()           # (slot) 0x48a0f0(unit, slot)
var on_free := Callable()             # (order) operator delete
var rand := Callable()                # (n) -> int, the shared 0x4b6c30 stream
var target_alive := Callable()        # (id) -> bool, target unit word +0xA6 != 0


static func s32(value: int) -> int:
	value &= MASK32
	return value - 0x100000000 if value & 0x80000000 else value


# ---------------------------------------------------------------- record

func make_order(type_id: int, target: int, pos, p36: int, p3a: int, p3e: int) -> Dictionary:
	## 0x43a0c0. Static flags are copied; 0x200 is stripped when no target is passed and 0x400 when no position is passed.
	## The target reference only links a live unit, and is dropped again when the (stripped) flags lack 0x200.
	type_id &= 0xff
	var flags: int = OrderTable.flags(type_id)
	var stored := target if target != 0 and (not target_alive.is_valid() or target_alive.call(target)) else 0
	if target == 0:
		flags &= ~OrderTable.F_TARGET
	if pos == null:
		flags &= ~OrderTable.F_POSITION
	if flags & OrderTable.F_TARGET == 0:
		stored = 0
	var p: Array = pos if pos != null else [0, 0, 0]
	var order := {
		id = next_id, type = type_id, state = 0, mask = 0, wake = NO_WAKE, owner = false, target = stored,
		x = s32(p[0]), y = s32(p[1]), z = s32(p[2]), leash = 0, last_seen = 0,
		p36 = s32(p36), p3a = s32(p3a), p3e = s32(p3e), flags = flags & MASK32, tick = tick & MASK32, pending = 0, goal = 0,
	}
	next_id += 1
	return order


func list_for(order: Dictionary) -> Array:
	return bg if order.flags & OrderTable.F_BACKGROUND else main


func head():
	return main[0] if not main.is_empty() else null


static func index_of(list: Array, order: Dictionary) -> int:
	for i in list.size():
		if list[i].id == order.id:
			return i
	return -1


static func _same(a, b) -> bool:
	return a != null and b != null and a.id == b.id


func destroy(order: Dictionary) -> void:
	## 0x43a1f0 (the order is already unlinked).
	if on_destroy.is_valid():
		on_destroy.call(order)
	if order.mask & 2 and destroy_notify.is_valid():
		destroy_notify.call(order)
	if order.flags & OrderTable.R_BUILDING:
		if stop_building.is_valid():
			stop_building.call(order)
		order.flags &= ~OrderTable.R_BUILDING
	if order.goal != 0:
		if cancel_goal.is_valid():
			cancel_goal.call(order)
		order.goal = 0
	if order.flags & OrderTable.R_SKIP_WEAPON_CLEAR == 0 and clear_weapon_targets.is_valid():
		clear_weapon_targets.call(3)
	order.owner = false


func _free(order: Dictionary) -> void:
	if on_free.is_valid():
		on_free.call(order)


func _unlink_destroy(order: Dictionary, seen_head) -> bool:
	## Shared removal: the list is chosen by the order's own 0x40000 flag; a miss removes nothing.
	## 0x10000 is set when the order is not the head the native routine read (seen_head may be null).
	var list := list_for(order)
	var i := index_of(list, order)
	if i < 0:
		return false
	list.remove_at(i)
	if not _same(order, seen_head):
		order.flags |= OrderTable.R_SKIP_WEAPON_CLEAR
	destroy(order)
	_free(order)
	return true


# ---------------------------------------------------------------- list helpers

func remove(order: Dictionary) -> bool:
	## 0x439f80: compares against the live main head (so a background order always gets 0x10000).
	return _unlink_destroy(order, head())


func clear_all(include_bg: bool) -> void:
	## 0x439eb0. Main: 0x4-protected orders survive unless include_bg; 0x10000 against the head read on entry.
	## Background (include_bg only): each order compared with the live main head (empty by then -> always 0x10000).
	var first = head()
	var i := 0
	while i < main.size():
		var order: Dictionary = main[i]
		if not include_bg and order.flags & OrderTable.F_PROTECTED:
			i += 1
			continue
		main.remove_at(i)
		if not _same(order, first):
			order.flags |= OrderTable.R_SKIP_WEAPON_CLEAR
		destroy(order)
		_free(order)
	if include_bg:
		while not bg.is_empty():
			if not _unlink_destroy(bg[0], head()):
				push_error("0x439eb0 would loop forever: background order without 0x40000")
				return


func rotate_to_tail(order: Dictionary) -> void:
	## 0x439fe0 (main list only).
	var i := index_of(main, order)
	if i < 0:
		return
	main.remove_at(i)
	main.append(order)


func push_front_inherit(order: Dictionary) -> void:
	## 0x43acb0 (and 0x43ac60 called with the list head): push onto bg or main by 0x40000, inherit the old head's 0x4000.
	var list := list_for(order)
	var old = list[0] if not list.is_empty() else null
	list.push_front(order)
	order.owner = true
	if old != null:
		order.flags |= old.flags & OrderTable.R_IDLE


func append(order: Dictionary) -> void:
	## 0x43ad10: tail of bg or main by 0x40000.
	list_for(order).append(order)
	order.owner = true


func marker_insert(order: Dictionary) -> void:
	## 0x43ad50 (also the tail of 0x43adc0): always the MAIN list. The new order takes the 0x1000 marker; it goes right
	## after the first order holding the marker (which loses it), or at the tail when none holds it.
	order.flags |= OrderTable.R_MARKER
	order.owner = true
	for i in main.size():
		if main[i].flags & OrderTable.R_MARKER:
			main[i].flags &= ~OrderTable.R_MARKER
			main.insert(i + 1, order)
			return
	main.append(order)


func patrol_append(order: Dictionary) -> void:
	## 0x43a020: unless some main order already has 0x8000, append a same-type order at the unit position (raw append,
	## no 0x1/0x1000). The calling order always gets 0x8000.
	var seen := false
	for other in main:
		if other.flags & OrderTable.R_PATROL_ORIGIN:
			seen = true
			break
	if not seen:
		var origin := make_order(order.type, 0, unit_pos.duplicate(), 0, 0, 0)
		append(origin)
	order.flags |= OrderTable.R_PATROL_ORIGIN


func find(type_id: int):
	## 0x439e30: first order of that type in the list its static flags select.
	var list: Array = bg if OrderTable.flags(type_id & 0xff) & OrderTable.F_BACKGROUND else main
	for order in list:
		if order.type == type_id & 0xff:
			return order
	return null


func count_builds(p36: int) -> int:
	## 0x439d80: sum of p3a over counted-build (0x100) orders with this p36, main then background.
	var total := 0
	for list in [main, bg]:
		for order in list:
			if order.flags & OrderTable.F_COUNTED_BUILD and order.p36 == s32(p36):
				total += order.p3a
	return s32(total)


# ---------------------------------------------------------------- issuing

func insert(type_id: int, shift: bool, target: int, pos, p36: int, p3a: int) -> Dictionary:
	## 0x43adc0.
	var order := make_order(type_id, target, pos, p36, p3a, 0)
	if not shift and order.flags & OrderTable.F_NO_CLEAR == 0:
		var first = head()
		var i := 0
		while i < main.size():
			var old: Dictionary = main[i]
			if old.flags & OrderTable.F_PROTECTED:
				i += 1
				continue
			main.remove_at(i)
			if not _same(old, first):
				old.flags |= OrderTable.R_SKIP_WEAPON_CLEAR
			destroy(old)
			_free(old)
	if order.flags & OrderTable.F_BACKGROUND == 0:
		# Head idle orders go even on shift issues, with no 0x10000.
		while not main.is_empty() and main[0].flags & OrderTable.R_IDLE:
			var idle: Dictionary = main[0]
			var list := list_for(idle)
			var i := index_of(list, idle)
			if i < 0:
				push_error("0x43adc0 would loop forever: idle head carries 0x40000")
				break
			list.remove_at(i)
			destroy(idle)
			_free(idle)
	order.flags |= OrderTable.R_ISSUED
	if not shift:
		order.flags |= OrderTable.R_ACKNOWLEDGE
	if order.flags & (OrderTable.F_BACKGROUND | OrderTable.F_HEAD):
		push_front_inherit(order)
	else:
		marker_insert(order)
	return order


static func _near(a: int, b: int) -> bool:
	## 0x43b004..0x43b029: (a - b + 0x100000) as u32 <= 0x200000 ("ja" exits), so exactly +-0x100000 still matches.
	return ((a - b + TOGGLE_HALF_WIDTH) & MASK32) <= 2 * TOGGLE_HALF_WIDTH


func issue(type_id: int, shift: bool, target: int, pos, p36: int, p3a: int):
	## 0x43afc0. With shift, the first MAIN order of the same type whose target matches (or no target passed) and whose
	## x and z are within 0x100000 (32-bit wrap; y and p36 ignored; no position passed matches any) is removed and nothing
	## is added. Returns the new order or null.
	if shift and not main.is_empty():
		var first = main[0]
		for order in main:
			if order.type != type_id & 0xff:
				continue
			if target != 0 and target != order.target:
				continue
			if pos != null and not (_near(pos[0], order.x) and _near(pos[2], order.z)):
				continue
			_unlink_destroy(order, first)
			return null
	return insert(type_id, shift, target, pos, p36, p3a)


func factory_count(type_id: int, p36: int, count: int) -> void:
	## 0x43b0b0 (factory build counts in p3a).
	type_id &= 0xff
	count = s32(count)
	var in_bg: bool = OrderTable.flags(type_id) & OrderTable.F_BACKGROUND != 0
	if count > 0:
		var list: Array = bg if in_bg else main
		var last = list.back() if not list.is_empty() else null
		if last != null and last.type == type_id and last.p36 == s32(p36):
			last.p3a = s32(last.p3a + count)
			return
		insert(type_id, true, 0, null, p36, count)
		return
	while true:
		var list: Array = bg if in_bg else main
		var hit = null
		for order in list:
			if order.type == type_id and order.p36 == s32(p36):
				hit = order
		if hit == null:
			return
		if hit.p3a > s32(-count):
			hit.p3a = s32(hit.p3a + count)
			return
		count = s32(count + hit.p3a)
		if not _unlink_destroy(hit, head()):
			push_error("0x43b0b0 would loop forever")
			return


# ---------------------------------------------------------------- dispatch

func _set_timer(order: Dictionary, spread: int) -> void:
	var r: int = rand.call(spread)
	order.mask |= 1
	order.wake = (tick + r + 30) & MASK32


func dispatch() -> void:
	## 0x43b7c0, once per unit tick. Loops on the live head in the same tick until an order waits or the queue ends.
	while true:
		if main.is_empty():
			_create_idle()
			return
		var order: Dictionary = main[0]
		if (tick & MASK32) >= order.wake:
			order.wake = NO_WAKE
			order.pending |= 1
		var ev: int = (order.pending | unit_ev) & order.mask
		if order.mask != 0 and ev == 0:
			return
		unit_ev = unit_ev & ~ev & 0xffff
		order.mask = 0
		order.pending &= ~ev & MASK32
		if ev & 0x10000 and aim_reset.is_valid():
			for slot in 3:
				aim_reset.call(slot)
		var code: int = int(handler.call(order, ev, false)) & MASK32
		match code:
			0:
				order.state = 0
			1:
				order.state = (order.state + 1) & 0xff
			2, 4:
				pass
			3:
				_set_timer(order, 15)
			5, 8:
				_unlink_destroy(order, head())
			6:
				rotate_to_tail(order)
			7:
				var first = head()
				while not main.is_empty():
					var old: Dictionary = main.pop_front()
					if not _same(old, first):
						old.flags |= OrderTable.R_SKIP_WEAPON_CLEAR
					destroy(old)
					_free(old)
				while not bg.is_empty():
					remove(bg[0])
				return
			9:
				# The native test is the record's own next pointer (+0x4A), i.e. the list that really holds the order,
				# while the removal searches the list chosen by 0x40000 (a background-flagged order placed in main by
				# 0x43ad50 has a successor but is never found, so nothing happens).
				order.flags |= OrderTable.R_CODE9
				var holder: Array = main if index_of(main, order) >= 0 else bg
				if index_of(holder, order) + 1 < holder.size():
					_unlink_destroy(order, head())
				else:
					order.state = 0
					_set_timer(order, 30)
			_:
				clear_all(true)
				return


func _create_idle() -> void:
	if not player_valid or (controller != 1 and controller != 2) or default_mission & 0xff == 0:
		return
	var order := make_order(default_mission, 0, null, 0, 0, 0)
	order.flags |= OrderTable.R_IDLE
	push_front_inherit(order)


func dispatch_bg() -> void:
	## 0x43bad0. Runs every background order whose mask is clear or whose wake has passed (wake is not reset), with ev 0,
	## restarting at the head after each handled order.
	var i := 0
	while i < bg.size():
		var order: Dictionary = bg[i]
		if order.mask != 0 and (tick & MASK32) < order.wake:
			i += 1
			continue
		order.mask = 0
		var code: int = int(handler.call(order, 0, true)) & MASK32
		match code:
			0:
				order.state = 0
			1:
				order.state = (order.state + 1) & 0xff
			2, 4:
				pass
			3:
				_set_timer(order, 15)
			6, 7:
				_unlink_destroy(order, head())
				return
			_:
				_unlink_destroy(order, head())
		i = 0


# ---------------------------------------------------------------- inspection

static func dump_order(order: Dictionary) -> Array:
	return [order.id, order.type, order.state, order.mask, order.wake, "unit" if order.owner else 0, order.target,
		order.x, order.y, order.z, order.leash, order.last_seen, order.p36, order.p3a, order.p3e, order.flags, order.tick,
		order.pending, order.goal]


func dump(list: Array) -> Array:
	return list.map(func(order): return dump_order(order))
