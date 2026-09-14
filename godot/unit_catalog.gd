extends RefCounted
## Shared original definition/model/script catalog. Generated content stays local.
var root: String
var index: Dictionary
var units: Dictionary = {}
var scripts: Dictionary = {}
var fault := ""

func _init(folder: String) -> void:
	root = folder
	var path := root.path_join("index.json")
	if not FileAccess.file_exists(path):
		fault = "Prepare the unit bundle with python tools/prepare_units.py"
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.has("units") or not parsed.has("build_menus"):
		fault = "Invalid unit bundle index"
		return
	index = parsed

func definition(unit_id: String) -> Dictionary:
	return index.get("units", {}).get(unit_id.to_lower(), {}).get("definition", {})

func movement(unit_id: String) -> Dictionary:
	return index.get("units", {}).get(unit_id.to_lower(), {}).get("movement", definition(unit_id))

func weapon(name: String) -> Dictionary:
	var item: Dictionary = index.get("weapons", {}).get(name.to_lower(), {})
	if item.is_empty():
		fault = "Unknown weapon: " + name
	elif not item.has("runtime") or not item.runtime.has("minimum_barrel_angle") or not item.runtime.has("start_velocity_raw_per_tick") or not item.runtime.has("acceleration_raw_per_tick_squared") or not item.runtime.has("turn_raw_per_tick") or not item.runtime.has("duration_ticks"):
		fault = "Prepare current weapon values with python tools/prepare_units.py"
		return {}
	return item

## Feature definition runtime fields (loader layout) or {} when unknown.
func feature(name: String) -> Dictionary:
	return index.get("features", {}).get(name.to_lower(), {}).get("runtime", {})

var feature_models: Dictionary = {}

func load_feature_model(name: String) -> Dictionary:
	name = name.to_lower()
	if feature_models.has(name):
		return feature_models[name]
	var entry: Dictionary = index.get("features", {}).get(name, {})
	if entry.get("model") == null:
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(str(entry.model))))
	if not value is Dictionary or not value.has("model"):
		fault = "Invalid feature model: " + name
		return {}
	feature_models[name] = value
	return value

func build_options(unit_id: String) -> Array:
	return index.get("build_menus", {}).get(unit_id.to_lower(), [])

func load_unit(unit_id: String) -> Dictionary:
	unit_id = unit_id.to_lower()
	if units.has(unit_id):
		return units[unit_id]
	if not index.get("units", {}).has(unit_id):
		fault = "Unknown unit: " + unit_id
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(index.units[unit_id].path)))
	if not value is Dictionary or value.get("id") != unit_id:
		fault = "Invalid unit data: " + unit_id
		return {}
	units[unit_id] = value
	return value

func load_script(unit_id: String) -> Dictionary:
	unit_id = unit_id.to_lower()
	if scripts.has(unit_id):
		return scripts[unit_id]
	var unit := load_unit(unit_id)
	if unit.is_empty() or unit.get("script") == null:
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(unit.script)))
	if not value is Dictionary:
		fault = "Invalid unit script: " + unit_id
		return {}
	scripts[unit_id] = value
	return value
