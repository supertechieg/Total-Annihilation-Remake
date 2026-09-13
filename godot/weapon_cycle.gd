extends RefCounted
## First primary-weapon host. Countdown ordering is provisional; VM callbacks are native-compared.
## The caller advances the VM before step(), and owns targeting, resources and projectiles.
var vm: RefCounted
const Queries = preload("res://weapon_queries.gd")
var queries: RefCounted
var definition: Dictionary
var runtime: Dictionary
var tick := 0
var aim_id := -1
var aimed := false
var requested := false
var remaining := 0
var next_shot := 0
var next_burst := 0
var shots: Array = []
var fault := ""
var heading := 0
var pitch := 0
var denied := false

func _init(script: RefCounted, weapon: Dictionary) -> void:
	vm = script
	queries = Queries.new(vm)
	definition = weapon.definition
	runtime = weapon.runtime
	for callback: String in ["AimPrimary", "QueryPrimary", "FirePrimary"]:
		if not vm.functions.has(callback):
			fault = "Missing primary weapon callback: " + callback
	if vm.functions.has("SetMaxReloadTime"):
		vm.invoke("SetMaxReloadTime", [int(int(runtime.reload_ticks) * 1000 / 30)])

func aim(target_heading: int, target_pitch: int) -> void:
	if not fault.is_empty():
		return
	heading = target_heading
	pitch = target_pitch
	requested = true
	remaining = 0
	request_aim()

func request_aim() -> void:
	aimed = false
	aim_id = vm.invoke("AimPrimary", [heading, pitch])

func stop() -> void:
	requested = false
	aimed = false
	aim_id = -1
	remaining = 0
	shots.clear()

func step(can_fire := true) -> void:
	tick += 1
	shots.clear()
	if not vm.fault.is_empty():
		fault = vm.fault
	if not fault.is_empty() or not requested:
		return
	if denied and can_fire:
		request_aim()
	denied = not can_fire
	if aim_id >= 0 and vm.completions.has(aim_id):
		var result: Dictionary = vm.completions[aim_id]
		aimed = result.reason == "return" and int(result.result) == 1
		aim_id = -1
	if not aimed or not can_fire:
		return
	if remaining == 0:
		if tick < next_burst:
			return
		remaining = maxi(1, int(definition.get("burst", "1")))
		next_shot = tick
		# Provisional policy: reload starts at burst start, not its final shot.
		next_burst = tick + maxi(1, int(runtime.reload_ticks))
	if tick < next_shot:
		return
	var query: int = vm.invoke("QueryPrimary", [0])
	if not vm.completions.has(query):
		fault = "Primary muzzle query did not finish synchronously"
		return
	var piece := int(vm.completions[query].locals[0])
	if piece < 0 or piece >= vm.pieces.size():
		fault = "Primary muzzle query returned an invalid piece"
		return
	vm.invoke("FirePrimary")
	if not vm.fault.is_empty():
		fault = vm.fault
		return
	shots.append({"tick": tick, "piece": piece, "piece_name": vm.pieces[piece].name,
		"velocity_raw_per_tick": int(runtime.velocity_raw_per_tick)})
	remaining -= 1
	next_shot = tick + maxi(1, int(runtime.burst_interval_ticks))
	if remaining == 0:
		# Cancel idle restoration and refresh aim before the next burst.
		request_aim()
