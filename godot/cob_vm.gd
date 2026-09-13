extends RefCounted
## COB v4 subset sufficient for ARMCOM.COB. No scene or rendering dependencies.
## See analysis/COB_VM.md for executable evidence and remaining fidelity limits.

const TICK_RATE := 30
const SLOT_COUNT := 8
const STACK_SIZE := 32
const BUDGET := 10000
var program: Dictionary
var instructions: Dictionary = {}
var functions: Dictionary = {}
var slots: Array = []
var statics: Array = []
var pieces: Array = []
var values: Dictionary = {}
var read_values: Dictionary = {}
var writable_values: Array[int] = [5]
var readback_values: Array[int] = []
var spin_targets: Array = []
var spin_acceleration: Array = []
var shading: Dictionary = {}
var caching: Dictionary = {}
var completions: Dictionary = {}
var events: Array = []
var fault := ""
var ticks := 0
var next_id := 1
var peak_threads := 0

func _init(data: Dictionary) -> void:
	program = data
	for instruction: Dictionary in data.instructions:
		instructions[int(instruction.address)] = instruction
	for i in range(data.functions.size()):
		functions[data.functions[i].name] = i
	statics.resize(int(data.static_count))
	statics.fill(0)
	slots.resize(SLOT_COUNT)
	slots.fill(null)
	for piece_name: String in data.pieces:
		spin_targets.append([0, 0, 0])
		spin_acceleration.append([0, 0, 0])
		pieces.append({"name": piece_name, "position": [0, 0, 0], "rotation": [0, 0, 0],
			"move_target": [0, 0, 0], "turn_target": [0, 0, 0],
			"move_speed": [0, 0, 0], "turn_speed": [0, 0, 0], "visible": true})

static func i32(value: int) -> int:
	var bits := value & 0xffffffff
	return bits - 0x100000000 if bits >= 0x80000000 else bits

static func trunc_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return absi(a) / absi(b) * (-1 if (a < 0) != (b < 0) else 1)

func record(kind: String, details: Dictionary = {}) -> void:
	var entry := details.duplicate(true)
	entry["tick"] = ticks
	entry["kind"] = kind
	events.append(entry)
	if events.size() > 2048:
		events.pop_front()

func fail(message: String) -> void:
	if fault.is_empty():
		fault = message
		record("fault", {"message": message})

func allocate(function_index: int, args: Array, mask: int) -> int:
	if function_index < 0 or function_index >= program.functions.size() or args.size() > STACK_SIZE:
		fail("Invalid script invocation")
		return -1
	var slot := -1
	for i in range(SLOT_COUNT):
		if slots[i] == null:
			slot = i
			break
	if slot < 0:
		fail("COB thread capacity exceeded (8 slots)")
		return -1
	var stack: Array = []
	stack.resize(STACK_SIZE)
	stack.fill(0)
	for i in range(args.size()):
		stack[i] = i32(int(args[i]))
	var info: Dictionary = program.functions[function_index]
	slots[slot] = {"id": next_id, "name": info.name, "pc": int(info.address), "sp": -1,
		"stack": stack, "mask": mask, "state": "ready", "remaining": 0,
		"wait_piece": 0, "wait_axis": 0, "wait_slot": -1}
	next_id += 1
	peak_threads = maxi(peak_threads, active_threads())
	record("start", {"slot": slot, "id": slots[slot].id, "function": info.name, "args": args})
	return slot

func invoke(function_name: String, args: Array = [], immediate := true) -> int:
	if not fault.is_empty():
		return -1
	if not functions.has(function_name):
		fail("Unknown callback: " + function_name)
		return -1
	var slot := allocate(int(functions[function_name]), args, 1)
	if slot < 0:
		return -1
	var id := int(slots[slot].id)
	if immediate:
		schedule(0)
	return id

func active_threads() -> int:
	var count := 0
	for thread in slots:
		if thread != null:
			count += 1
	return count

func finish(slot: int, result: int, reason := "return") -> void:
	var thread: Dictionary = slots[slot]
	completions[int(thread.id)] = {"result": result, "reason": reason, "tick": ticks,
		"locals": thread.stack.duplicate(), "function": thread.name}
	if completions.size() > 256:
		completions.erase(completions.keys()[0])
	record(reason, {"slot": slot, "id": thread.id, "function": thread.name, "result": result})
	slots[slot] = null
	for other in slots:
		if other != null and other.state == "call" and int(other.wait_slot) == slot:
			other.state = "ready"

func push(thread: Dictionary, value: int) -> void:
	if int(thread.sp) + 1 >= STACK_SIZE:
		fail("COB stack overflow at %s" % thread.pc)
		return
	thread.sp = int(thread.sp) + 1
	thread.stack[int(thread.sp)] = i32(value)

func pop(thread: Dictionary) -> int:
	if int(thread.sp) < 0:
		fail("COB stack underflow at %s" % thread.pc)
		return 0
	var result := int(thread.stack[int(thread.sp)])
	thread.sp = int(thread.sp) - 1
	return result

func step() -> void:
	if not fault.is_empty():
		return
	ticks += 1
	schedule(1)
	if fault.is_empty():
		advance_pieces()

func schedule(elapsed_ticks: int) -> void:
	# Slot order matters: a new child in a higher slot runs in this pass.
	for slot in range(SLOT_COUNT):
		if not fault.is_empty():
			return
		if slots[slot] == null:
			continue
		var thread: Dictionary = slots[slot]
		match String(thread.state):
			"sleep":
				thread.remaining = int(thread.remaining) - elapsed_ticks
				if int(thread.remaining) <= 0:
					thread.state = "ready"
			"turn", "move":
				var key := "turn_speed" if thread.state == "turn" else "move_speed"
				if int(pieces[int(thread.wait_piece)][key][int(thread.wait_axis)]) == 0:
					thread.state = "ready"
		if thread.state == "ready":
			run_slot(slot)

func run_slot(slot: int) -> void:
	for _operation in range(BUDGET):
		if slots[slot] == null or not fault.is_empty():
			return
		var thread: Dictionary = slots[slot]
		if thread.state != "ready":
			return
		var pc := int(thread.pc)
		if not instructions.has(pc):
			fail("PC is not an instruction boundary: %d" % pc)
			return
		var instruction: Dictionary = instructions[pc]
		var args: Array = instruction.args
		var op := String(instruction.name)
		thread.pc = pc + 1 + args.size()
		match op:
			"PUSH_CONSTANT":
				push(thread, int(args[0]))
			"CREATE_LOCAL":
				# Locals occupy the bottom of the same stack; preserve preseeded args.
				if int(thread.sp) + 1 >= STACK_SIZE:
					fail("Too many COB locals")
				else:
					thread.sp = int(thread.sp) + 1
			"PUSH_LOCAL", "POP_LOCAL":
				var index := int(args[0])
				if index < 0 or index >= STACK_SIZE:
					fail("Local index out of range")
				elif op == "PUSH_LOCAL":
					push(thread, int(thread.stack[index]))
				else:
					thread.stack[index] = pop(thread)
			"PUSH_STATIC":
				push(thread, int(statics[int(args[0])]))
			"POP_STATIC":
				statics[int(args[0])] = pop(thread)
			"POP_STACK":
				pop(thread)
			"ADD", "SUB", "MUL", "DIV", "EQ", "NE", "LT", "LE", "GT", "GE", "AND", "OR", "XOR", "BIT_AND", "BIT_OR", "BIT_XOR":
				var b := pop(thread)
				var a := pop(thread)
				var result := 0
				match op:
					"ADD": result = i32(a + b)
					"SUB": result = i32(a - b)
					"MUL": result = i32(a * b)
					"DIV":
						if b == 0:
							fail("Division by zero")
						else:
							result = trunc_div(a, b)
					"EQ": result = int(a == b)
					"NE": result = int(a != b)
					"LT": result = int(a < b)
					"LE": result = int(a <= b)
					"GT": result = int(a > b)
					"GE": result = int(a >= b)
					"AND": result = int(a != 0 and b != 0)
					"OR": result = int(a != 0 or b != 0)
					"XOR": result = int((a != 0) != (b != 0))
					"BIT_AND": result = a & b
					"BIT_OR": result = a | b
					"BIT_XOR": result = a ^ b
				push(thread, result)
			"NOT":
				push(thread, int(pop(thread) == 0))
			"BIT_NOT":
				push(thread, ~pop(thread))
			"JUMP":
				thread.pc = int(args[0])
			"JUMP_IF_ZERO":
				if pop(thread) == 0:
					thread.pc = int(args[0])
			"HIDE", "SHOW":
				var piece: Dictionary = pieces[int(args[0])]
				piece.visible = op == "SHOW"
				record("visibility", {"piece": piece.name, "visible": piece.visible, "pc": pc})
			"DONT_SHADE", "SHADE":
				shading[int(args[0])] = op == "SHADE"
			"DONT_CACHE", "CACHE":
				caching[int(args[0])] = op == "CACHE"
			"SPIN", "STOP_SPIN":
				var index := int(args[0])
				var axis := int(args[1])
				if op == "SPIN":
					pieces[index].turn_target[axis] = -1
					spin_targets[index][axis] = trunc_div(pop(thread), TICK_RATE)
					spin_acceleration[index][axis] = trunc_div(pop(thread), TICK_RATE)
				else:
					spin_targets[index][axis] = 0
					spin_acceleration[index][axis] = -trunc_div(pop(thread), TICK_RATE)
				if spin_acceleration[index][axis] == 0:
					pieces[index].turn_speed[axis] = spin_targets[index][axis]
			"MOVE", "TURN", "MOVE_NOW", "TURN_NOW":
				var target := pop(thread)
				var speed := 0
				if op == "MOVE" or op == "TURN":
					speed = pop(thread)
				set_motion(int(args[0]), int(args[1]), op, target, speed)
			"WAIT_TURN", "WAIT_MOVE":
				# Always yields, even if already at target; resume on next schedule.
				thread.state = "turn" if op == "WAIT_TURN" else "move"
				thread.wait_piece = int(args[0])
				thread.wait_axis = int(args[1])
			"SLEEP":
				thread.remaining = trunc_div(i32(pop(thread) * TICK_RATE), 1000)
				thread.state = "sleep"
			"START_SCRIPT", "CALL_SCRIPT":
				var count := int(args[1])
				var parameters: Array = []
				parameters.resize(count)
				for i in range(count - 1, -1, -1):
					parameters[i] = pop(thread)
				var child := allocate(int(args[0]), parameters, int(thread.mask))
				if op == "CALL_SCRIPT":
					thread.state = "call"
					thread.wait_slot = child
			"RETURN":
				finish(slot, pop(thread))
			"SET_SIGNAL_MASK":
				thread.mask = pop(thread)
			"SIGNAL":
				var mask := pop(thread)
				for other in range(SLOT_COUNT):
					if slots[other] != null and (int(slots[other].mask) & mask) != 0:
						finish(other, 0, "signal")
			"GET_VALUE":
				var key := pop(thread)
				if key in readback_values:
					push(thread, int(values.get(key, 0)))
				elif not read_values.has(key):
					fail("Unsupported simulation read: %d" % key)
				else:
					push(thread, int(read_values[key]))
			"SET_VALUE":
				var value := pop(thread)
				var key := pop(thread)
				if key not in writable_values:
					fail("Unsupported simulation value: %d" % key)
				else:
					values[key] = value
					record("value", {"key": key, "value": value})
			_:
				fail("Unsupported opcode %s at %d" % [op, pc])
	fail("COB execution exceeded instruction budget without yielding")

func set_motion(index: int, axis: int, op: String, destination: int, speed: int) -> void:
	var piece: Dictionary = pieces[index]
	var turning := op.begins_with("TURN")
	var key := "rotation" if turning else "position"
	var speed_key := "turn_speed" if turning else "move_speed"
	var target_key := "turn_target" if turning else "move_target"
	var target := destination & 65535 if turning else destination
	var current := int(piece[key][axis])
	piece[target_key][axis] = target
	if op.ends_with("NOW"):
		piece[key][axis] = target
		piece[speed_key][axis] = 0
	else:
		var velocity := trunc_div(speed, TICK_RATE)
		var difference := target - current
		if turning:
			# Original comparison uses > 0x8000, preserving the sign at an exact half-turn.
			if absi(difference) > 32768:
				difference -= 65536 * (1 if difference > 0 else -1)
		if turning:
			piece[speed_key][axis] = velocity * (1 if difference > 0 else -1) if difference != 0 else 0
		else:
			# Native MOVE retains positive velocity at an already-reached target until the motion update.
			piece[speed_key][axis] = velocity * (-1 if difference < 0 else 1)
	record("motion", {"piece": piece.name, "axis": axis, "op": op, "target": target, "speed": speed})

func advance_pieces() -> void:
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		for axis in range(3):
			var acceleration := int(spin_acceleration[index][axis])
			if acceleration != 0:
				var speed := i32(int(piece.turn_speed[axis]) + acceleration)
				var target := int(spin_targets[index][axis])
				if (acceleration > 0 and speed >= target) or (acceleration < 0 and speed <= target):
					speed = target
					spin_acceleration[index][axis] = 0
				piece.turn_speed[axis] = speed
			for turning: bool in [false, true]:
				var key := "rotation" if turning else "position"
				var speed_key := "turn_speed" if turning else "move_speed"
				var target_key := "turn_target" if turning else "move_target"
				var velocity := int(piece[speed_key][axis])
				if velocity == 0:
					continue
				var current := int(piece[key][axis])
				var target := int(piece[target_key][axis])
				if turning and target == -1:
					piece.rotation[axis] = (current + velocity) & 65535
					continue
				var remaining := target - current
				if turning:
					remaining = ((target - current) if velocity > 0 else (current - target)) & 65535
				if absi(remaining) <= absi(velocity):
					piece[key][axis] = target
					piece[speed_key][axis] = 0
				else:
					piece[key][axis] = ((current + velocity) & 65535) if turning else i32(current + velocity)

func snapshot() -> Dictionary:
	var threads: Array = []
	for thread in slots:
		if thread != null:
			threads.append({"id": thread.id, "function": thread.name, "pc": thread.pc, "state": thread.state})
	return {"tick": ticks, "statics": statics.duplicate(), "pieces": pieces.duplicate(true),
		"values": values.duplicate(), "threads": threads, "fault": fault}
