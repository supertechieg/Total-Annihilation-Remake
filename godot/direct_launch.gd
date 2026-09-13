extends RefCounted
const Ground = preload("res://ground_motion.gd")

static func solve(source: Array, target: Array, speed: int, start_speed := 0, acceleration := 0) -> Dictionary:
	var x := Ground.signed32(int(source[0]) - int(target[0]))
	var y := Ground.signed32(int(source[1]) - int(target[1]))
	var z := Ground.signed32(int(source[2]) - int(target[2]))
	var distance := int(sqrt(float(x) * x + float(z) * z))
	var heading := roundi(atan2(float(x), float(z)) * 10430.37835047) & 65535
	var pitch := roundi(atan2(float(-Ground.signed16(y >> 16)), float(Ground.signed16(distance >> 16))) * 10430.37835047) & 65535
	var trig := Ground.new()
	var initial_speed: int = start_speed if start_speed != 0 else (0 if acceleration != 0 else speed)
	var horizontal := trig.velocity_component(pitch, initial_speed, 16384)
	return {"heading": heading, "pitch": pitch, "distance": distance, "initial_speed": initial_speed,
		"velocity": [-trig.velocity_component(heading, horizontal, 0), trig.velocity_component(pitch, initial_speed, 0), -trig.velocity_component(heading, horizontal, 16384)]}
