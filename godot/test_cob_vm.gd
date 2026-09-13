extends SceneTree

const VM = preload("res://cob_vm.gd")
var failures := 0
var checks := 0
var real_program: Dictionary

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func program(routines: Array, names: Array, piece_names: Array = ["body"]) -> Dictionary:
	var result := {"static_count": 1, "pieces": piece_names, "functions": [], "instructions": []}
	var pc := 0
	for r in range(routines.size()):
		result.functions.append({"name": names[r], "address": pc})
		for instruction: Array in routines[r]:
			result.instructions.append({"address": pc, "name": instruction[0], "args": instruction[1]})
			pc += 1 + instruction[1].size()
	return result

func step_many(vm, count: int) -> void:
	for _i in range(count):
		vm.step()
	check(vm.fault.is_empty(), "VM remains healthy: " + vm.fault)

func piece(vm, name: String) -> Dictionary:
	for item: Dictionary in vm.pieces:
		if item.name == name:
			return item
	return {}

func test_sleep_and_calls() -> void:
	var vm = VM.new(program([
		[["CALL_SCRIPT", [1, 0]], ["PUSH_CONSTANT", [7]], ["RETURN", []]],
		[["PUSH_CONSTANT", [40]], ["SLEEP", []], ["PUSH_CONSTANT", [0]], ["RETURN", []]]
	], ["parent", "child"]))
	var parent: int = vm.invoke("parent")
	check(vm.active_threads() == 2, "CALL uses a separate slot")
	check(vm.slots[1].remaining == 1, "40ms truncates to one 30Hz tick")
	vm.step()
	check(not vm.completions.has(parent), "Parent's lower slot is not rerun after child returns")
	vm.step()
	check(vm.completions[parent].result == 7, "Parent resumes next pass; child result not pushed onto its stack")
	var wait_vm = VM.new(program([[["WAIT_TURN", [0, 0]], ["PUSH_CONSTANT", [1]], ["RETURN", []]]], ["wait"]))
	var id: int = wait_vm.invoke("wait")
	check(not wait_vm.completions.has(id), "Wait always yields even at target")
	wait_vm.step()
	check(wait_vm.completions[id].result == 1, "Wait resumes on following scheduler pass")

func test_arithmetic_and_arguments() -> void:
	var vm = VM.new(program([[
		["CREATE_LOCAL", []], ["CREATE_LOCAL", []], ["PUSH_LOCAL", [0]], ["PUSH_LOCAL", [1]],
		["SUB", []], ["RETURN", []]]], ["subtract"]))
	var id: int = vm.invoke("subtract", [7, 12])
	check(vm.completions[id].result == -5, "Arguments retain order and CREATE_LOCAL preserves their values")
	vm = VM.new(program([[["PUSH_CONSTANT", [2147483647]], ["PUSH_CONSTANT", [1]], ["ADD", []], ["RETURN", []]]], ["overflow"]))
	id = vm.invoke("overflow")
	check(vm.completions[id].result == -2147483648, "Signed 32-bit addition wraps")
	check(VM.trunc_div(-8192, 30) == -273, "Signed division truncates toward zero")

func test_motion() -> void:
	var vm = VM.new(program([[
		["PUSH_CONSTANT", [65500]], ["TURN_NOW", [0, 1]],
		["PUSH_CONSTANT", [300]], ["PUSH_CONSTANT", [14]], ["TURN", [0, 1]],
		["WAIT_TURN", [0, 1]], ["PUSH_CONSTANT", [1]], ["RETURN", []]]], ["turn"]))
	var id: int = vm.invoke("turn")
	vm.step()
	check(vm.pieces[0].rotation[1] == 65510, "Turn takes short positive path across angle wrap")
	step_many(vm, 4)
	check(vm.pieces[0].rotation[1] == 14 and vm.pieces[0].turn_speed[1] == 0, "Turn clamps at destination")
	check(not vm.completions.has(id), "Wait sees piece completion on next tick, after movement update")
	vm.step()
	check(vm.completions[id].result == 1, "Wait returns after motion finishes")
	vm = VM.new(program([[["PUSH_CONSTANT", [300]], ["PUSH_CONSTANT", [0]], ["MOVE", [0, 0]], ["PUSH_CONSTANT", [0]], ["RETURN", []]]], ["same_target"]))
	vm.invoke("same_target")
	check(vm.pieces[0].move_speed[0] == 10, "Native MOVE retains velocity at target before motion update")
	vm.step()
	check(vm.pieces[0].move_speed[0] == 0 and vm.pieces[0].position[0] == 0, "Motion update clears already-reached MOVE")

func test_limits_and_unknowns() -> void:
	var vm = VM.new(program([[["PUSH_CONSTANT", [1000]], ["SLEEP", []]]], ["sleep"]))
	for _i in range(8):
		vm.invoke("sleep", [], false)
	check(vm.active_threads() == 8, "Eight simultaneous slots available")
	check(vm.invoke("sleep", [], false) == -1 and not vm.fault.is_empty(), "Ninth slot fails explicitly")
	vm = VM.new(program([[["UNSUPPORTED", []]]], ["bad"]))
	vm.invoke("bad")
	check(vm.fault.contains("Unsupported opcode"), "Unsupported instructions are not silently ignored")
	vm = VM.new(program([[["POP_STACK", []]]], ["bad"]))
	vm.invoke("bad")
	check(vm.fault.contains("underflow"), "Stack underflow detected")

func test_commander() -> void:
	var vm = VM.new(real_program)
	vm.invoke("Create")
	check(vm.fault.is_empty(), "Original Create runs")
	check(vm.statics == [0, 0, 1, 0], "Original initial state variables")
	for name: String in ["rbigflash", "lfirept", "nanospray"]:
		check(not piece(vm, name).visible, "Create hides " + name)
	check(vm.active_threads() == 1 and vm.slots[1].name == "MotionControl", "Create launches persistent MotionControl")
	var query: int = vm.invoke("QueryNanoPiece", [0])
	check(vm.completions[query].locals[0] == 4, "Query modifies output parameter")
	vm.invoke("StartMoving")
	step_many(vm, 4)
	check(piece(vm, "pelvis").position[1] == -114688, "First compiled walk pelvis keyframe")
	check(piece(vm, "lthigh").rotation[0] == (-7616 & 65535), "First compiled walk thigh keyframe")
	check(piece(vm, "torso").rotation[1] == 768, "First compiled walk torso keyframe")
	vm.step()
	check(piece(vm, "torso").rotation[1] == 704, "Next keyframe after compiled 40ms sleep")
	vm.invoke("StopMoving")
	step_many(vm, 100)
	check(vm.statics[0] == 0, "StopMoving changes original movement flag")
	for name: String in ["lthigh", "rthigh", "lleg", "rleg"]:
		check(piece(vm, name).rotation[0] == 0, "Original stop routine settles " + name)
	check(piece(vm, "pelvis").position[1] == 0, "Stop settles pelvis")
	vm.invoke("FirePrimary")
	check(piece(vm, "lfirept").visible, "Fire callback shows muzzle flash")
	step_many(vm, 2)
	check(piece(vm, "lfirept").visible, "100ms flash remains through tick two")
	vm.step()
	check(not piece(vm, "lfirept").visible, "100ms flash hides on third tick")
	var aim: int = vm.invoke("AimPrimary", [8192, 0])
	step_many(vm, 90)
	check(vm.completions.has(aim) and vm.completions[aim].result == 1, "Original AimPrimary completes")
	check(piece(vm, "torso").rotation[1] == 8192, "Aim heading reaches exact COB angle")
	check(piece(vm, "luparm").rotation[0] == (-5461 & 65535), "Aim pitch offset from compiled instructions")
	var interrupted: int = vm.invoke("AimPrimary", [16000, 0])
	var newer: int = vm.invoke("AimTertiary", [-8192, 0])
	check(vm.completions.has(interrupted) and vm.completions[interrupted].reason == "signal", "New aim signals and terminates prior aim")
	step_many(vm, 90)
	check(vm.completions.has(newer) and vm.completions[newer].result == 1, "D-gun aim completes after signal")
	check(piece(vm, "torso").rotation[1] == (-8192 & 65535), "D-gun heading uses signed argument")
	vm.invoke("TargetCleared", [0])
	step_many(vm, 90)
	check(vm.statics[1] == 0 and vm.statics[3] == 0, "TargetCleared restores aiming flags")
	vm.invoke("StartBuilding", [4096, 0])
	step_many(vm, 90)
	check(vm.values.get(5, 0) == 1, "StartBuilding sets INBUILDSTANCE")
	vm.invoke("StopBuilding")
	step_many(vm, 90)
	check(vm.values.get(5, -1) == 0 and vm.statics[1] == 0, "StopBuilding clears stance and restores pose")
	check(vm.peak_threads <= 8, "Original callbacks remain within slot capacity")
	var path := ProjectSettings.globalize_path("res://../local/scripts/vm-test-trace.json")
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify({"snapshot": vm.snapshot(), "events": vm.events}, "  "))

func run() -> void:
	var path := ProjectSettings.globalize_path("res://../local/viewer-assets/armcom.cob.json")
	if not FileAccess.file_exists(path):
		printerr("Prepare assets first")
		quit(1)
		return
	real_program = JSON.parse_string(FileAccess.get_file_as_string(path))
	test_sleep_and_calls()
	test_arithmetic_and_arguments()
	test_motion()
	test_limits_and_unknowns()
	test_commander()
	print("COB_VM_CHECKS %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
