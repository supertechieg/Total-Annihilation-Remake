extends RefCounted
## Native launch velocity from supplied weapon-controller state.
const Ground = preload("res://ground_motion.gd")
var trig := Ground.new()

func velocity(heading: int, pitch: int, speed: int, gravity: int, travel: int) -> Array:
	assert(speed > 0, "Ballistic launch requires positive weapon speed")
	@warning_ignore("integer_division")
	var elapsed: int = (travel & 0xffffffff) / speed
	var horizontal: int = trig.velocity_component(pitch, speed, 16384)
	return [Ground.signed32(-trig.velocity_component(heading, horizontal, 0)),
		Ground.signed32(trig.velocity_component(pitch, speed, 0) - elapsed * gravity),
		Ground.signed32(-trig.velocity_component(heading, horizontal, 16384))]
