extends SceneTree
const VM = preload("res://cob_vm.gd")
const Catalog = preload("res://unit_catalog.gd")
const Cycle = preload("res://weapon_cycle.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
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
	print("WEAPON_CYCLE %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
