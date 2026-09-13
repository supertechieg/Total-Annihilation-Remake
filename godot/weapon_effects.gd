extends RefCounted
var root: String
var index: Dictionary = {}
var textures: Dictionary = {}

func _init(folder: String) -> void:
	root = folder
	var path := root.path_join("index.json")
	if FileAccess.file_exists(path):
		index = JSON.parse_string(FileAccess.get_file_as_string(path)).get("effects", {})

func frames(key: String) -> Array:
	return index.get(key.to_lower(), {}).get("frames", [])

func texture(filename: String) -> Texture2D:
	if not textures.has(filename):
		var image := Image.load_from_file(root.path_join(filename))
		if image == null:
			return null
		textures[filename] = ImageTexture.create_from_image(image)
	return textures[filename]
