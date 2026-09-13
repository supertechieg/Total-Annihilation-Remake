extends SceneTree
const VM = preload("res://cob_vm.gd")
const Catalog = preload("res://unit_catalog.gd")
const Cycle = preload("res://weapon_cycle.gd")
var checks := 0
var failures := 0

class ImmediateRecoil extends RefCounted:
	var functions := {"AimPrimary": 0, "QueryPrimary": 1, "FirePrimary": 2}
	var fault := ""
	var completions := {}
	var pieces := [{"name": "barrel"}]
	var position := Vector3(10, 20, 30)
	var invocation := 0
	func invoke(callback: String, _args: Array = []) -> int:
		invocation += 1
		if callback == "QueryPrimary":
			completions[invocation] = {"locals": [0]}
		elif callback == "FirePrimary":
			position = Vector3(40, 50, 60)
		elif callback == "AimPrimary":
			completions[invocation] = {"reason": "return", "result": 1}
		return invocation

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var recoil := ImmediateRecoil.new()
	var recoil_cycle := Cycle.new(recoil, catalog.weapon("EMG"))
	var resolutions := [0]
	var resolver := func(_piece: String) -> Vector3:
		resolutions[0] += 1
		return recoil.position
	recoil_cycle.step(false, resolver)
	check(resolutions[0] == 0, "Muzzle is not resolved when no shot is emitted")
	recoil_cycle.aim(0, 0)
	recoil_cycle.step(true, resolver)
	check(recoil.position == Vector3(40, 50, 60), "Firing callback applies immediate recoil")
	check(recoil_cycle.shots.size() == 1 and recoil_cycle.shots[0].position == Vector3(10, 20, 30), "Shot retains muzzle position from before firing callback")
	check(resolutions[0] == 1, "Muzzle resolves once per emitted shot")
	var vm = VM.new(catalog.load_script("armflash"))
	vm.read_values = {4: 100, 17: 0}
	vm.invoke("Create")
	var cycle = Cycle.new(vm, catalog.weapon("EMG"))
	cycle.aim(8192, 1024)
	vm.step()
	cycle.step()
	check(cycle.shots.is_empty(), "No shot before turret aiming completes")
	var shots: Array = []
	var aim_correct := true
	for tick in range(60):
		vm.step()
		cycle.step()
		shots.append_array(cycle.shots)
		if not cycle.shots.is_empty():
			aim_correct = aim_correct and int(vm.pieces[2].rotation[1]) == 8192
		if shots.size() == 6:
			break
	check(shots.size() == 6, "Two three-shot EMG bursts emitted")
	check(aim_correct, "Turret remains aimed during repeated bursts")
	if shots.size() == 6:
		check(shots[1].tick - shots[0].tick == 3 and shots[2].tick - shots[1].tick == 3, "Burst uses original converted interval")
		check(shots[3].tick - shots[0].tick == 12, "Host reload policy uses original converted reload")
		check([shots[0].piece, shots[1].piece, shots[2].piece] == [0, 0, 1], "Overlapping shots use native-compared queried barrels")
		check(shots[0].velocity_raw_per_tick == 655359, "Shot carries original converted velocity")
	cycle.stop()
	var stopped_shots := 0
	for tick in range(40):
		vm.step()
		cycle.step()
		stopped_shots += cycle.shots.size()
	check(stopped_shots == 0, "Stopped weapon emits no new shots")
	cycle.aim(-8192, 2048)
	for tick in range(60):
		vm.step()
		cycle.step(false)
	check(cycle.aimed and cycle.shots.is_empty(), "Host can deny firing while aim completes")
	cycle.step(true)
	check(cycle.shots.is_empty(), "Permission recovery refreshes potentially restored turret aim")
	for tick in range(80):
		vm.step()
		cycle.step(true)
		if not cycle.shots.is_empty():
			break
	check(cycle.shots.size() == 1 and int(vm.pieces[2].rotation[1]) == (-8192 & 65535), "Firing resumes only after turret returns to aim")
	cycle.aim(32768, 0)
	cycle.aim(0, 0)
	for tick in range(80):
		vm.step()
		cycle.step(false)
	check(cycle.aimed, "Replacement aim waits for newest script invocation")
	var sustained_shots := 0
	for tick in range(600):
		vm.step()
		cycle.step()
		sustained_shots += cycle.shots.size()
	check(sustained_shots >= 100, "Sustained firing continues without accumulating blocked callbacks")
	check(cycle.fault.is_empty() and vm.fault.is_empty(), "Repeated aiming and firing remain fault-free")
	var raider_vm = VM.new(catalog.load_script("corraid"))
	raider_vm.read_values = {4: 100, 17: 0}
	raider_vm.invoke("Create")
	var cannon = Cycle.new(raider_vm, catalog.weapon("CORE_LIGHTCANNON"))
	cannon.aim(8192, 1024)
	var cannon_shots: Array = []
	var cannon_aim_correct := true
	for tick in range(300):
		raider_vm.step()
		cannon.step()
		for shot: Dictionary in cannon.shots:
			cannon_shots.append(shot)
			cannon_aim_correct = cannon_aim_correct and int(raider_vm.pieces[2].rotation[1]) == 8192
	check(cannon_shots.size() >= 5, "Raider cannon sustains single-shot cycles")
	check(cannon_aim_correct, "Raider turret is aimed when cannon fires")
	var cannon_values_correct := true
	for index in range(cannon_shots.size()):
		var shot: Dictionary = cannon_shots[index]
		cannon_values_correct = cannon_values_correct and shot.piece_name == "flare" and int(shot.velocity_raw_per_tick) == 371370
		if index > 0:
			cannon_values_correct = cannon_values_correct and int(shot.tick) - int(cannon_shots[index - 1].tick) >= 45
	check(cannon_values_correct, "Raider uses queried flare, converted speed and reload gate")
	check(cannon.fault.is_empty() and raider_vm.fault.is_empty(), "Raider repeated firing remains fault-free")
	print("WEAPON_CYCLE %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
