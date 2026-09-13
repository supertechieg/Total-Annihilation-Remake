extends RefCounted
## Original WAV streams prepared locally; repeated events share decoded streams.
var root: String
var streams: Dictionary = {}
var fault := ""

func _init(folder: String) -> void:
	root = folder

func sound(name: String) -> AudioStreamWAV:
	name = name.to_lower()
	if name.is_empty():
		return null
	if name.contains("/") or name.contains("\\") or name in [".", ".."]:
		fault = "Invalid sound name"
		return null
	if streams.has(name):
		return streams[name]
	var path := root.path_join(name + ".wav")
	if not FileAccess.file_exists(path):
		fault = "Prepare weapon sounds with python tools/prepare_weapon_sounds.py"
		return null
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		fault = "Unable to decode weapon sound: " + name
		return null
	streams[name] = stream
	return stream
