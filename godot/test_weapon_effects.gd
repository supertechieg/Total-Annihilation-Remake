extends SceneTree
const Effects = preload("res://weapon_effects.gd")
func _initialize() -> void:
	var effects := Effects.new(ProjectSettings.globalize_path("res://../local/weapon-effects/"))
	var count := 0
	var failures: Array = []
	for key: String in effects.index:
		for frame: Dictionary in effects.frames(key):
			count += 1
			var texture := effects.texture(frame.file)
			if texture == null or texture.get_width() != int(frame.width) or texture.get_height() != int(frame.height) or effects.texture(frame.file) != texture:
				failures.append(frame.file)
	if count == 0:
		failures.append("No prepared effects")
	var report := {"animations": effects.index.size(), "frames": count, "failures": failures,
		"scope": "Godot texture loading, frame dimensions and texture caching for prepared original explosion artwork; excludes original renderer comparison and animation timing"}
	FileAccess.open("res://../analysis/weapon-effect-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("WEAPON_EFFECTS %d frames, %d failures" % [count, failures.size()])
	quit(0 if failures.is_empty() else 1)
