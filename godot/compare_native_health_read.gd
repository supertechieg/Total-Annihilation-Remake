extends SceneTree
## Compares VM.health_read against the original GET_VALUE 4 callback 0x480770 (tools/native_health_read.py).
const VM = preload("res://cob_vm.gd")

func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://../local/")
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("scripts/native-health-read.json")))
	var failures := 0
	var differences: Array = []
	for case: Array in trace.cases:
		# The native callback returns eax as an unsigned word; the COB stack stores it as a signed 32-bit value.
		var expected := VM.i32(int(case[2]))
		var actual := VM.health_read(int(case[0]), int(case[1]))
		if actual != expected:
			failures += 1
			if differences.size() < 8:
				differences.append({"health": case[0], "maxdamage": case[1], "actual": actual, "expected": expected})
	print("NATIVE_HEALTH_READ_COMPARISON %d / %d cases match %s" % [trace.cases.size() - failures, trace.cases.size(), JSON.stringify(differences)])
	quit(0 if failures == 0 else 1)
