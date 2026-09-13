extends SceneTree
const Sounds = preload("res://weapon_sounds.gd")
func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://../local/weapon-sounds/")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("index.json")))
	var sounds := Sounds.new(root)
	var failures: Array = []
	for name: String in index.sounds:
		var stream := sounds.sound(name)
		var metadata: Dictionary = index.sounds[name]
		if stream == null:
			failures.append(name)
			continue
		var expected := float(metadata.frames) / float(metadata.rate)
		if absf(stream.get_length() - expected) > 1.0 / float(metadata.rate) or sounds.sound(name) != stream:
			failures.append(name)
	var report := {"sounds": index.sounds.size(), "failures": failures, "scope": "Godot WAV decoding, sample-duration agreement and stream cache identity for locally prepared weapon sounds; excludes audible playback and event timing"}
	FileAccess.open("res://../analysis/weapon-sound-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("WEAPON_SOUNDS %d / %d decoded and cached" % [index.sounds.size() - failures.size(), index.sounds.size()])
	quit(0 if failures.is_empty() else 1)
