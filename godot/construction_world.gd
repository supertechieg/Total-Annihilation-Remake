extends RefCounted
## First construction/economy host. Accounting settlement and placement are provisional.
const BuildMath = preload("res://construction_math.gd")
const VM = preload("res://cob_vm.gd")
var scripts: Dictionary = {}
var catalog: RefCounted
var navigation: RefCounted
var units: Dictionary = {}
var next_id := 1
var builder_id := 0
var task_id := 0
var unit_limit := 1000
var energy := 1000.0
var metal := 1000.0
var base_energy_storage := 1000.0
var base_metal_storage := 1000.0
var energy_storage := 1000.0
var metal_storage := 1000.0
var completed: Array[int] = []
var status := "Idle"
var ticks := 0
var builder_ready := true

func _init(source: RefCounted, terrain: RefCounted, commander_position: Vector2, commander := "armcom") -> void:
	catalog = source
	navigation = terrain
	builder_id = add_unit(commander, commander_position, 0.0)

func add_unit(type: String, position: Vector2, remaining: float) -> int:
	var id := next_id
	next_id += 1
	var definition: Dictionary = catalog.definition(type)
	units[id] = {"id": id, "type": type, "position": position, "remaining": remaining,
		"health": 1 if remaining > 0 else int(definition.get("maxdamage", "1")), "active": true}
	# Enable only the building script whose healthy lifecycle has a native oracle.
	if type == "armsolar":
		var vm = VM.new(catalog.load_script(type))
		vm.read_values = {4: 100, 17: ceili(remaining * 100)}
		vm.writable_values.assign([1, 5, 20])
		vm.invoke("Create")
		if remaining == 0:
			vm.invoke("Activate")
		scripts[id] = vm
	return id

func set_active(id: int, active: bool) -> bool:
	if not scripts.has(id) or float(units[id].remaining) > 0:
		return false
	if bool(units[id].active) != active:
		units[id].active = active
		scripts[id].invoke("Activate" if active else "Deactivate")
	return true

func footprint(type: String, position: Vector2) -> Rect2:
	var definition: Dictionary = catalog.definition(type)
	var size := Vector2(float(definition.get("footprintx", "1")), float(definition.get("footprintz", "1"))) * 16.0
	return Rect2(position - size * 0.5, size)

func in_build_range(type: String, point: Vector2) -> bool:
	var bounds := footprint(type, point)
	var builder: Dictionary = units[builder_id]
	var closest: Vector2 = builder.position.clamp(bounds.position, bounds.end)
	var distance := float(catalog.definition(builder.type).get("builddistance", "60"))
	return builder.position.distance_to(closest) <= distance

func placement_error(type: String, point: Vector2) -> String:
	if units.size() >= unit_limit:
		return "Unit limit reached"
	if type not in catalog.build_options(units[builder_id].type):
		return "Commander cannot build that unit"
	var bounds := footprint(type, point)
	if bounds.position.x < 0 or bounds.position.y < 0 or bounds.end.x >= navigation.width * 16 or bounds.end.y >= navigation.height * 16:
		return "Outside map"
	var low := 255
	var high := 0
	for y in range(int(bounds.position.y / 16), int(ceil(bounds.end.y / 16))):
		for x in range(int(bounds.position.x / 16), int(ceil(bounds.end.x / 16))):
			var value: int = navigation.heights[y * navigation.width + x]
			low = mini(low, value)
			high = maxi(high, value)
	var definition: Dictionary = catalog.definition(type)
	if high - low > int(definition.get("maxslope", "10")):
		return "Terrain is too steep"
	if navigation.sea_level - low > int(definition.get("maxwaterdepth", "0")) or navigation.sea_level - high < int(definition.get("minwaterdepth", "-255")):
		return "Invalid water depth"
	for unit: Dictionary in units.values():
		if bounds.intersects(footprint(unit.type, unit.position)):
			return "Space occupied"
	if not in_build_range(type, point):
		return "Move Commander closer to build site"
	return ""

func begin_build(type: String, point: Vector2) -> int:
	point = point.snapped(Vector2(16, 16))
	var error := placement_error(type, point)
	if not error.is_empty():
		status = error
		return 0
	if float(catalog.definition(type).get("buildtime", "0")) <= 0:
		status = "Unit has no valid build time"
		return 0
	task_id = add_unit(type, point, 1.0)
	status = "Building " + catalog.definition(type).get("name", type)
	return task_id

func stop_build() -> void:
	task_id = 0
	status = "Build paused"

func resume_build(id: int) -> bool:
	if not units.has(id) or float(units[id].remaining) <= 0:
		return false
	if not in_build_range(units[id].type, units[id].position):
		status = "Move Commander closer to resume"
		return false
	task_id = id
	status = "Building " + catalog.definition(units[id].type).get("name", units[id].type)
	return true

func step() -> void:
	ticks += 1
	completed.clear()
	for id: int in scripts:
		# Construction health is not combat damage. Damaged smoke awaits its opcodes.
		scripts[id].read_values[17] = ceili(float(units[id].remaining) * 100)
		scripts[id].step()
	var energy_income := 0.0
	var metal_income := 0.0
	energy_storage = base_energy_storage
	metal_storage = base_metal_storage
	for unit: Dictionary in units.values():
		if float(unit.remaining) > 0:
			continue
		var fields: Dictionary = catalog.definition(unit.type)
		energy_storage += float(fields.get("energystorage", "0"))
		metal_storage += float(fields.get("metalstorage", "0"))
		energy_income += float(fields.get("energymake", "0"))
		metal_income += float(fields.get("metalmake", "0"))
		if bool(unit.active):
			energy_income -= float(fields.get("energyuse", "0"))
	energy = clampf(energy + energy_income / 30.0, 0.0, energy_storage)
	metal = clampf(metal + metal_income / 30.0, 0.0, metal_storage)
	if task_id == 0 or not builder_ready:
		return
	var unit: Dictionary = units[task_id]
	var builder: Dictionary = units[builder_id]
	var builder_fields: Dictionary = catalog.definition(builder.type)
	if not in_build_range(unit.type, unit.position):
		status = "Build paused: out of range"
		return
	var fields: Dictionary = catalog.definition(unit.type)
	var input := {"remaining": unit.remaining, "health": unit.health,
		"energy_cost": float(fields.get("buildcostenergy", "0")), "metal_cost": float(fields.get("buildcostmetal", "0")),
		"build_time": int(fields.buildtime), "max_health": int(fields.get("maxdamage", "1")),
		"work": float(builder_fields.get("workertime", "0")) / 30.0, "energy_debt": 0.0, "metal_debt": 0.0}
	var result := BuildMath.advance(input)
	# Temporary immediate-payment host, distinct from TA's deferred debt settlement.
	if result.energy_requested > energy or result.metal_requested > metal:
		status = "Build paused: insufficient resources"
		return
	if result.accepted:
		energy -= result.energy_accepted
		metal -= result.metal_accepted
		unit.remaining = result.remaining
		unit.health = result.health
		status = "Building %s · %d%%" % [catalog.definition(unit.type).get("name", unit.type), roundi((1.0 - float(unit.remaining)) * 100)]
		if float(unit.remaining) == 0:
			if scripts.has(task_id):
				scripts[task_id].read_values[17] = 0
				scripts[task_id].invoke("Activate")
			completed.append(task_id)
			task_id = 0
			status = "Construction complete"
