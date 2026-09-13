extends RefCounted
## Native-verified steering with provisional terrain routing/arrival integration.
const Motion = preload("res://ground_motion.gd")
var motion = Motion.new()
var navigation: RefCounted
var position_raw: Array = [0, 0]
var heading := 0
var speed := 0
var turn_step := 0
var route := PackedVector2Array()
var route_index := 1
var flags := 0
var height := 0
var status := "Idle"
var ticks := 0
var definition: Dictionary
var script_vm: RefCounted
var callbacks: Array[String] = []

func _init(nav: RefCounted, fields: Dictionary, start: Vector2, vm: RefCounted = null) -> void:
	navigation = nav
	definition = fields
	script_vm = vm
	position_raw = [int(start.x * 65536), int(start.y * 65536)]
	height = navigation.height_at(start)

func point() -> Vector2:
	return Vector2(float(position_raw[0]) / 65536.0, float(position_raw[1]) / 65536.0)

func move_to(target: Vector2) -> bool:
	var candidate: PackedVector2Array = navigation.path(point(), target)
	if candidate.is_empty():
		status = navigation.failure
		return false
	route = candidate
	route_index = 1
	status = "Moving"
	return true

func stop() -> void:
	route.clear()
	status = "Stopping"

func emit_movement(blocked: bool) -> void:
	var max_speed := int(float(definition.get("maxvelocity", "1.2")) * 65536)
	var transition := Motion.animation_transition({"speed": speed, "turn_step": turn_step,
		"movement_flags": 4 if blocked else 0, "attached": false, "unit_flags": flags,
		"rate1": int(float(definition.get("moverate1", str(max_speed * 2 / 65536.0))) * 65536),
		"rate2": int(float(definition.get("moverate2", str(max_speed * 2 / 65536.0))) * 65536)})
	flags = transition.unit_flags
	callbacks.assign(transition.callbacks)
	if script_vm != null:
		for callback: String in callbacks:
			if script_vm.functions.has(callback):
				script_vm.invoke(callback)

func step() -> void:
	ticks += 1
	var points: Array = []
	if not route.is_empty():
		while route_index < route.size() - 1 and point().distance_to(route[route_index]) < 5.0:
			route_index += 1
		if point().distance_to(route[-1]) < 2.0 and speed <= 19660:
			route.clear()
			status = "Arrived"
		else:
			for vertex: Vector2 in [route[route_index - 1], route[route_index], route[-1]]:
				points.append([int(vertex.x * 65536), int(vertex.y * 65536)])
	var data := {"position": position_raw, "waypoints": points, "speed": speed,
		"heading": heading, "turn_rate": int(definition.get("turnrate", "1044")),
		"max_speed": int(float(definition.get("maxvelocity", "1.2")) * 65536),
		"acceleration": int(float(definition.get("acceleration", "0.15")) * 65536),
		"brake": int(float(definition.get("brakerate", "0.3")) * 65536),
		"pitch": 0, "height_integer": height, "sea_level": navigation.sea_level, "unit_flags": 0}
	var result := motion.steer(data)
	heading = result.heading
	speed = result.speed
	turn_step = result.turn_step
	var proposed := Vector2(float(int(position_raw[0]) + int(result.velocity[0])) / 65536.0,
		float(int(position_raw[1]) + int(result.velocity[2])) / 65536.0)
	var blocked: bool = not navigation.can_cross(navigation.cell_at(point()), navigation.cell_at(proposed))
	if blocked:
		speed = 0
		if turn_step != 0 and not route.is_empty():
			# Provisional collision response: retain a valid route while turning in place.
			status = "Turning around obstruction"
		else:
			route.clear()
			status = "Route blocked"
	else:
		if status == "Turning around obstruction":
			status = "Moving"
		position_raw[0] = int(position_raw[0]) + int(result.velocity[0])
		position_raw[1] = int(position_raw[1]) + int(result.velocity[2])
		height = navigation.height_at(point())
	if route.is_empty() and speed == 0 and status == "Stopping":
		status = "Idle"
	emit_movement(blocked)
