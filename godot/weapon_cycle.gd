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

var slot := "Primary"

func _init(script: RefCounted, weapon: Dictionary, weapon_slot := "Primary") -> void:
	vm = script
	slot = weapon_slot
	queries = Queries.new(vm, slot)
	definition = weapon.definition
	runtime = weapon.runtime
	# Undefined callbacks are skipped like the original name lookups (0x4b0940/0x4b0a70 -> 0x4b0b00 return 0):
	# no Aim reports "not aimed" (never fires), no Query keeps muzzle piece 0, and no Fire still launches.
	# Only the primary host sets the script's reload hint (original 0x49e070 sends one value for all weapons).
	if slot == "Primary" and vm.functions.has("SetMaxReloadTime"):
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
	# A missing or dropped Aim start reports 0 through the engine callback (0x4b0b11), leaving aimed false.
	aim_id = vm.invoke("Aim" + slot, [heading, pitch]) if vm.functions.has("Aim" + slot) else -1

func stop() -> void:
	requested = false
	aimed = false
	aim_id = -1
	remaining = 0
	shots.clear()

func step(can_fire := true, resolve_muzzle := Callable(), reload_delay := -1, world_tick := -1) -> void:
	tick = tick + 1 if world_tick < 0 else world_tick
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
		# One script dispatch creates a projectile-owned burst source.
		remaining = 1
		next_shot = tick
	if tick < next_shot:
		return
	# Native 0x43e240 keeps its initial local 0 when QueryPrimary is undefined or cannot get a slot.
	var piece := 0
	if vm.functions.has("Query" + slot):
		var query: int = vm.invoke("Query" + slot, [0])
		if query >= 0:
			if not vm.completions.has(query):
				fault = slot + " muzzle query did not finish synchronously"
				return
			piece = int(vm.completions[query].locals[0])
	if piece < 0 or piece >= vm.pieces.size():
		fault = slot + " muzzle query returned an invalid piece"
		return
	# Native launch consumes the queried position before FirePrimary can alter pose.
	var shot := {"tick": tick, "piece": piece, "piece_name": vm.pieces[piece].name,
		"velocity_raw_per_tick": int(runtime.velocity_raw_per_tick), "burst": int(definition.get("burst", "0"))}
	if resolve_muzzle.is_valid():
		shot.position = resolve_muzzle.call(str(shot.piece_name))
	# Native launchers (0x49cb94/0x49cd4f/0x49cf73) start Fire by name after creating the projectile and ignore the result.
	if vm.functions.has("Fire" + slot):
		vm.invoke("Fire" + slot)
	if not vm.fault.is_empty():
		fault = vm.fault
		return
	shots.append(shot)
	# Settle only successful dispatch; projectile-owned rounds do not reset reload.
	next_burst = tick + maxi(1, int(runtime.reload_ticks) if reload_delay < 0 else reload_delay)
	remaining -= 1
	next_shot = tick + maxi(1, int(runtime.burst_interval_ticks))
	if remaining == 0:
		# Cancel idle restoration and refresh aim before the next burst.
		request_aim()
