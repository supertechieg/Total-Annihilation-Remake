extends SceneTree
const Wind = preload("res://wind_state.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var wind := Wind.new()
	var input := {"tick": 1000, "next_tick": 100, "minimum": 0, "maximum": 0,
		"normalization": 1000, "strength": 100, "heading": 18209, "drift": [12, 34, 56],
		"ratio": 0.5, "crt_seed": 2644478673, "game_seed": 914425625}
	var calm := wind.advance(input)
	check(calm.next_tick == 340 and calm.crt_seed == 681214544, "Calm update uses native CRT interval from previous deadline")
	check(calm.strength == 0 and calm.heading == 18209 and calm.game_seed == 914425625, "Calm wind preserves heading and skips bounded RNG draws")
	check(calm.drift == [0, 34, 0] and calm.ratio == 0.0, "Wind changes horizontal drift and preserves vertical component")
	input.tick = 100
	var unchanged := wind.advance(input)
	check(unchanged.changed == 0 and unchanged.next_tick == 100 and unchanged.crt_seed == input.crt_seed and unchanged.game_seed == input.game_seed and unchanged.drift == input.drift, "Equal deadline does not consume randomness or update wind")
	input.tick = 99
	check(wind.advance(input) == unchanged, "Before deadline remains unchanged")
	input.tick = 1000
	input.minimum = 100
	input.maximum = 101
	input.crt_seed = 3351513989
	input.game_seed = 684146864
	var narrow := wind.advance(input)
	check(narrow.next_tick == 460 and narrow.heading == 63418 and narrow.game_seed == 828897210 and narrow.strength == 100, "Single-value range skips strength RNG but draws heading")
	check(narrow.drift == [42, 34, -196] and narrow.ratio == 0.10000000149011612, "Native quantized drift and float32 ratio match")
	input.minimum = 1000
	input.maximum = 2000
	input.crt_seed = 1696328432
	input.game_seed = 1019629047
	var strong := wind.advance(input)
	check(strong.next_tick == 520 and strong.strength == 1516 and strong.heading == 56524 and strong.game_seed == 1221713100 and strong.drift == [2320, 34, -1952] and strong.ratio == 1.0, "Strong wind uses both RNG draws and caps normalized strength")
	print("WIND_STATE %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
