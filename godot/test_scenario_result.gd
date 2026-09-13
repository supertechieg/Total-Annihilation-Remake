extends SceneTree
const Result = preload("res://scenario_result.gd")
func _initialize() -> void:
	var state := Result.new()
	var units := {1: {"team": 0}, 2: {"team": 1, "remaining": 1.0}}
	var checks := [state.update(units, 1) == "active"]
	units.erase(2)
	checks.append(state.update(units, 1) == "victory")
	units.erase(1)
	checks.append(state.update(units, 1) == "victory")
	state = Result.new()
	checks.append(state.update({2: {"team": 1}}, 1) == "defeat")
	checks.append(state.update({1: {"team": 0}}, 1) == "defeat")
	state = Result.new()
	checks.append(state.update({}, 1) == "defeat")
	print("SCENARIO_RESULT %d / %d checks pass" % [checks.size() - checks.count(false), checks.size()])
	quit(0 if checks.count(false) == 0 else 1)
