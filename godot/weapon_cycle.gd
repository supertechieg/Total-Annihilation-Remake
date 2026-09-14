extends RefCounted
## One weapon entry of the original per-slot weapon update 0x49e1a0 (unit + 4 + slot * 0x1c) and its fire callback:
## turret 0x49d580 (tolerance 0x49d880) or vlaunch 0x49db70. See analysis/WEAPON_AIM.md.
## Per update: reload countdown, target check (loss clears the request bit), Aim issue when not requested, then a fire
## attempt when the reload is 0. The VM callbacks are native-compared; the caller supplies targeting, angles and range.
## The caller steps the VM before update(): Aim is started with run-now 0 and first runs in the next VM pass, which in
## this host ordering (VM pass, then weapons) is the same single scheduler pass the original gives it before the
## following weapon update (0x49e1a0 at 0x48adda, then the script pass 0x4b0d60 at 0x48adeb).
const Queries = preload("res://weapon_queries.gd")
const SLOT_INDEX := {"Primary": 0, "Secondary": 1, "Tertiary": 2}
## Target states reported by the caller, as returned by 0x48a1e0.
const TARGET_NONE := 0
const TARGET_VALID := 1
## A unit target found dead: 0x48a1e0 clears the target words and starts TargetCleared(slot) with run-now 0.
const TARGET_DEAD := 2
## Fire callback selected by 0x49e010: turret (flag 0x80000) 0x49d580 or vlaunch (0x10) 0x49db70. The remaining
## callbacks (0x49d9c0 for lineofsight/selfprop, 0x49dd60 for dropped) are not ported; such weapons are hosted as turrets.
enum Kind {TURRET, VLAUNCH}

var vm: RefCounted
var queries: RefCounted
var definition: Dictionary
var runtime: Dictionary
var slot := "Primary"
var kind := Kind.TURRET
var tick := 0
## Entry +0x1b bit 0: an Aim call was issued and has not been consumed by a shot, a failed re-solve/tolerance check or
## target loss. Set even when the start was dropped or the script lacks the function.
var requested := false
## Entry +8: cleared when Aim is issued and after a shot; completion callback 0x481490 stores 1 for any nonzero return.
var result := 0
## Entry +0x16/+0x18: angles sent with the last Aim (the turret callback adds the unit heading and spread when firing).
var heading := 0
var pitch := 0
## Started Aim invocations whose completion may still arrive; every one of them reports into the same entry.
var aim_ids: Array = []
## World tick at which the reload countdown (entry +0x14) reaches 0.
var next_burst := 0
var shots: Array = []
## Per update: [{"type": "aim"|"target_cleared"|"attempt"|"completion", ...}] for comparison and debugging.
var events: Array = []
## Unit +0xbb bit 0x10 set during this update (failed range gate or failed turret re-solve).
var range_failed := false
var fault := ""
## Angles used by the aim()/step() host helpers: [ok, heading, pitch].
var static_solve = null

var aimed: bool:
	get:
		return result != 0

func _init(script: RefCounted, weapon: Dictionary, weapon_slot := "Primary") -> void:
	vm = script
	slot = weapon_slot
	queries = Queries.new(vm, slot)
	definition = weapon.definition
	runtime = weapon.runtime
	kind = Kind.VLAUNCH if flag("vlaunch") and not flag("turret") else Kind.TURRET
	# Undefined callbacks are skipped like the original name lookups (0x4b0940/0x4b0a70 -> 0x4b0b00 return 0):
	# no Aim reports "not aimed" (never fires), no Query keeps muzzle piece 0, and no Fire still launches.
	# Only the primary host sets the script's reload hint (original 0x49e070 sends one value for all weapons).
	if slot == "Primary" and vm.functions.has("SetMaxReloadTime"):
		vm.invoke("SetMaxReloadTime", [int(int(runtime.reload_ticks) * 1000 / 30)])

func flag(key: String) -> bool:
	return int(str(definition.get(key, "0")).to_int()) & 1 != 0

## Native flags byte +0x1b: present (bit 1), slot index (bits 2-3), request (bit 0).
func flags_byte() -> int:
	return 2 | (int(SLOT_INDEX.get(slot, 0)) << 2) | (1 if requested else 0)

func reload_remaining() -> int:
	return maxi(0, next_burst - tick)

## Host helper: aim at fixed relative angles (used by tests and simple hosts). Issues Aim now when none is requested.
func aim(target_heading: int, target_pitch: int) -> void:
	static_solve = [true, target_heading, target_pitch]
	if fault.is_empty() and not requested:
		if kind == Kind.TURRET:
			heading = target_heading & 0xffff
			pitch = target_pitch & 0xffff
			issue_aim(heading, pitch)
		else:
			issue_aim(0, 0)

## Order ended: equivalent to the next update finding no target (bit 0 cleared); result and reload are kept.
func stop() -> void:
	requested = false
	static_solve = null
	shots.clear()

## Host helper around update() for a fixed aim(); can_fire false holds the fire attempt without touching the state.
func step(can_fire := true, resolve_muzzle := Callable(), reload_delay := -1, world_tick := -1) -> void:
	update({"tick": tick + 1 if world_tick < 0 else world_tick, "target": TARGET_VALID if static_solve != null else TARGET_NONE,
		"solve": static_solve if static_solve != null else [false, 0, 0], "permit": can_fire,
		"resolve_muzzle": resolve_muzzle, "reload_delay": reload_delay})

## One 0x49e1a0 slot pass. Context keys:
## tick, target (TARGET_*), solve [ok, heading, pitch] (turret angles relative to the unit, from the current AimFrom
## and target point; the same values serve the Aim issue and the callback re-solve, which happen in the same update),
## unit_heading, unit_flags (unit +0x110, bits 0xc widen the default tolerance), in_range (0x49aa80), affordable
## (stock covers energy/metal per shot), permit (host-only hold), resolve_muzzle Callable(piece name) -> position,
## line_angles Callable(piece name) -> [heading, pitch] (vlaunch 0x49db70 muzzle-to-target angles),
## spread Callable(heading, pitch) -> [heading, pitch] (turret 0x49d580), launch (projectile creation succeeds),
## reload_delay (reload word written after a shot; -1 uses runtime.reload_ticks).
func update(context: Dictionary) -> void:
	tick = int(context.get("tick", tick + 1))
	shots.clear()
	events.clear()
	range_failed = false
	collect_completions()
	if not vm.fault.is_empty():
		fault = vm.fault
	if not fault.is_empty():
		return
	var target := int(context.get("target", TARGET_VALID))
	if target != TARGET_VALID:
		if target == TARGET_DEAD and vm.functions.has("TargetCleared"):
			var started: int = vm.invoke("TargetCleared", [int(SLOT_INDEX.get(slot, 0))], false)
			events.append({"type": "target_cleared", "started": started >= 0})
		# 0x49e1ea: the request bit is cleared and the slot is skipped (no fire attempt).
		requested = false
		return
	var solve: Array = context.get("solve", [false, 0, 0])
	if kind == Kind.TURRET and not requested:
		if bool(solve[0]):
			heading = int(solve[1]) & 0xffff
			pitch = int(solve[2]) & 0xffff
			issue_aim(heading, pitch)
	elif kind == Kind.VLAUNCH and not requested:
		# 0x49e33d..0x49e386: vlaunch weapons send Aim(0, 0) and do not store angles (stockpile gating not modelled).
		issue_aim(0, 0)
	# 0x49e3ae: fire attempt only once the reload countdown is 0.
	if reload_remaining() != 0:
		return
	if not bool(context.get("permit", true)):
		return
	if not bool(context.get("in_range", true)):
		range_failed = true
		return
	if not bool(context.get("affordable", true)):
		return
	events.append({"type": "attempt"})
	if kind == Kind.TURRET:
		fire_turret(context, solve)
	else:
		fire_vlaunch(context)

## 0x49e31c/0x49e386: result = 0, Aim<slot>(heading, pitch) with run-now 0 (return ignored), request bit set.
func issue_aim(aim_heading: int, aim_pitch: int) -> void:
	result = 0
	var name := "Aim" + slot
	var id := -1
	if vm.functions.has(name):
		# A dropped start (all eight slots busy) calls the completion with 0 (0x4b0b11), which leaves result 0.
		id = vm.invoke(name, [aim_heading, aim_pitch], false)
	if id >= 0:
		aim_ids.append(id)
		if aim_ids.size() > 32:
			aim_ids.pop_front()
	events.append({"type": "aim", "args": [aim_heading, aim_pitch], "started": id >= 0})
	requested = true

## Completion callback 0x481490: a RETURN with a nonzero value stores result = 1; zero, SIGNAL kills and faults do not.
func collect_completions() -> void:
	var pending: Array = []
	for id: int in aim_ids:
		if vm.completions.has(id):
			var completion: Dictionary = vm.completions[id]
			if str(completion.reason) == "return" and int(completion.result) != 0:
				result = 1
			events.append({"type": "completion", "value": int(completion.result), "reason": str(completion.reason)})
		elif thread_alive(id):
			pending.append(id)
	aim_ids = pending

func thread_alive(id: int) -> bool:
	if not "slots" in vm:
		return true
	for thread in vm.slots:
		if thread != null and int(thread.id) == id:
			return true
	return false

## 0x49d880: default tolerance 150 (2000 when unit +0x110 & 0xc) for both axes when def +0x106 is 0; otherwise
## tolerance and pitchtolerance (falling back to tolerance), compared with the signed 16-bit angle differences.
static func tolerance_ok(stored_heading: int, stored_pitch: int, new_heading: int, new_pitch: int, tolerance: int, pitch_tolerance: int, unit_flags: int) -> bool:
	var heading_limit := tolerance & 0xffff
	var pitch_limit := pitch_tolerance & 0xffff
	if heading_limit == 0:
		heading_limit = 2000 if unit_flags & 0xc else 150
		pitch_limit = heading_limit
	elif pitch_limit == 0:
		pitch_limit = heading_limit
	return absi(signed16(stored_heading - new_heading)) <= heading_limit and absi(signed16(stored_pitch - new_pitch)) <= pitch_limit

static func signed16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value & 0x8000 else value

## Turret callback 0x49d580.
func fire_turret(context: Dictionary, solve: Array) -> void:
	if not requested or result == 0:
		return
	if not bool(solve[0]):
		# 0x49d65b: re-solve failure clears the request and sets unit +0xbb bit 0x10.
		requested = false
		range_failed = true
		return
	if not tolerance_ok(heading, pitch, int(solve[1]), int(solve[2]), int(str(definition.get("tolerance", "0")).to_int()),
			int(str(definition.get("pitchtolerance", "0")).to_int()), int(context.get("unit_flags", 0))):
		# 0x49d68a: out of tolerance clears the request; Aim is issued again on the next update.
		requested = false
		return
	var piece := muzzle_piece()
	if piece < 0:
		return
	# 0x49d6b4: the stored heading becomes absolute, then the spread draws perturb both stored angles.
	heading = (heading + int(context.get("unit_heading", 0))) & 0xffff
	var spread: Callable = context.get("spread", Callable())
	if spread.is_valid():
		var perturbed: Array = spread.call(heading, pitch)
		heading = int(perturbed[0]) & 0xffff
		pitch = int(perturbed[1]) & 0xffff
	if emit(context, piece):
		# 0x49d78b..0x49d797.
		result = 0
		requested = false

## Vlaunch callback 0x49db70: gated by result only; stores muzzle-to-target angles, launches, clears result and bit 0.
func fire_vlaunch(context: Dictionary) -> void:
	if result == 0:
		return
	var piece := muzzle_piece()
	if piece < 0:
		return
	var angles: Callable = context.get("line_angles", Callable())
	if angles.is_valid():
		var values: Array = angles.call(str(vm.pieces[piece].name))
		heading = int(values[0]) & 0xffff
		pitch = int(values[1]) & 0xffff
	if emit(context, piece):
		result = 0
		requested = false

## Native 0x43e240 keeps its initial local 0 when Query<slot> is undefined or cannot get a slot.
func muzzle_piece() -> int:
	var piece := 0
	if vm.functions.has("Query" + slot):
		var query: int = vm.invoke("Query" + slot, [0])
		if query >= 0:
			if not vm.completions.has(query):
				fault = slot + " muzzle query did not finish synchronously"
				return -1
			piece = int(vm.completions[query].locals[0])
	if piece < 0 or piece >= vm.pieces.size():
		fault = slot + " muzzle query returned an invalid piece"
		return -1
	return piece

## Projectile launch: the queried position is consumed before Fire<slot> can alter the pose; the launchers
## (0x49cb94/0x49cd4f/0x49cf73) start Fire by name after creating the projectile and ignore the result.
## Returns true when the launch succeeded (0x49e43f), which also writes the reload countdown.
func emit(context: Dictionary, piece: int) -> bool:
	if not bool(context.get("launch", true)):
		return false
	var shot := {"tick": tick, "piece": piece, "piece_name": vm.pieces[piece].name, "heading": heading, "pitch": pitch,
		"velocity_raw_per_tick": int(runtime.get("velocity_raw_per_tick", 0)), "burst": int(str(definition.get("burst", "0")).to_int())}
	var resolve_muzzle: Callable = context.get("resolve_muzzle", Callable())
	if resolve_muzzle.is_valid():
		shot.position = resolve_muzzle.call(str(shot.piece_name))
	if vm.functions.has("Fire" + slot):
		# Run-now 0: the thread first runs in the next VM pass, like Aim.
		vm.invoke("Fire" + slot, [], false)
	if not vm.fault.is_empty():
		fault = vm.fault
		return false
	shots.append(shot)
	# 0x49e468..0x49e4ee: reload word = supplied settlement; decremented once per update before the fire attempt.
	var delay := int(context.get("reload_delay", -1))
	next_burst = tick + ((int(runtime.get("reload_ticks", 0)) if delay < 0 else delay) & 0xffff)
	return true
