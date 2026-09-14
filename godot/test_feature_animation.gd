extends SceneTree
## 2D feature sprites: shared GAF animation stepping (0x4b8b90) and the 0x46a610 draw anchor.
const FeatureAnimation = preload("res://feature_animation.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var durations := [3, 1, 2]
	var state := FeatureAnimation.start(durations)
	check(state.active and state.index == 0 and state.counter == 3, "Animation starts at frame 0 with its duration")
	var changes: Array = []
	for tick in range(12):
		if FeatureAnimation.step(state, durations, true):
			changes.append([tick, int(state.index)])
	# Counter 3 -> 2 -> 1, advance; frame 1 (counter 1) advances next tick; frame 2 (counter 2) holds one tick; wrap.
	check(changes == [[2, 1], [3, 2], [5, 0], [8, 1], [9, 2], [11, 0]], "Counters of 2+ count down, others advance and loop: %s" % [changes])
	var once := FeatureAnimation.start([1, 1])
	check(FeatureAnimation.step(once, [1, 1], false) and once.index == 1, "A counter of 1 advances immediately")
	check(FeatureAnimation.step(once, [1, 1], false) and not once.active and once.index == 2, "Non-looping sequences stop with the index at the frame count")
	check(not FeatureAnimation.step(once, [1, 1], false), "Stopped sequences no longer change")
	var zero := FeatureAnimation.start([0, 0])
	check(FeatureAnimation.step(zero, [0, 0], true) and zero.index == 1, "Zero durations advance every tick")
	var flat := PackedByteArray()
	flat.resize(16)
	flat.fill(0)
	check(FeatureAnimation.anchor(flat, 4, 4, 1, 2, 1, 1) == Vector2i(24, 40), "Anchor is the footprint centre on flat ground")
	check(FeatureAnimation.anchor(flat, 4, 4, 0, 0, 3, 2) == Vector2i(24, 16), "Odd footprints centre at half-cell offsets")
	var hills := PackedByteArray([10, 20, 0, 0, 30, 41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	check(FeatureAnimation.anchor(hills, 4, 4, 0, 0, 2, 2) == Vector2i(16, 16 - ((10 + 20 + 30 + 41) >> 3)), "Height lift is the anchor cell's corner sum shifted right by three")
	check(FeatureAnimation.anchor(flat, 4, 4, 0, 0, 0xffff, 1) == Vector2i(-8, 8), "Negative footprint shorts truncate toward zero")
	print("FEATURE_ANIMATION %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
