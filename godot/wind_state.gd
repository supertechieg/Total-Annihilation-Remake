extends RefCounted
## Original wind update with explicit RNG states; not yet scheduled by the world.
const Ground = preload("res://ground_motion.gd")
var trig := Ground.new()
var game_seed := 1

func bounded_random(bound: int) -> int:
	if bound < 2:
		return 0
	game_seed = (game_seed * 16807) % 2147483647
	if game_seed == 0:
		game_seed = 2147483647
	return game_seed % bound

func advance(input: Dictionary) -> Dictionary:
	var result := {"next_tick": int(input.next_tick), "strength": int(input.strength),
		"heading": int(input.heading), "drift": input.drift.duplicate(), "ratio": float(input.ratio),
		"changed": 0, "crt_seed": int(input.crt_seed), "game_seed": int(input.game_seed)}
	if (int(input.next_tick) & 0xffffffff) >= (int(input.tick) & 0xffffffff):
		return result
	result.crt_seed = (int(input.crt_seed) * 214013 + 2531011) & 0xffffffff
	var random15 := (int(result.crt_seed) >> 16) & 32767
	@warning_ignore("integer_division")
	var interval: int = (random15 * 10 / 32768 + 5) * 30
	result.next_tick = (int(result.next_tick) + interval) & 0xffffffff
	game_seed = int(input.game_seed)
	result.strength = int(input.minimum) + bounded_random(int(input.maximum) - int(input.minimum))
	if int(result.strength) != 0:
		result.heading = bounded_random(65536)
	result.game_seed = game_seed
	result.drift[0] = Ground.signed32(-2 * trig.velocity_component(int(result.heading), int(result.strength), 0))
	result.drift[2] = Ground.signed32(-2 * trig.velocity_component(int(result.heading), int(result.strength), 16384))
	var encoded := PackedByteArray()
	encoded.resize(4)
	encoded.encode_float(0, float(result.strength) / float(input.normalization))
	result.ratio = minf(encoded.decode_float(0), 1.0)
	result.changed = 1
	return result
