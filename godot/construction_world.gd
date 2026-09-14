extends RefCounted
## Construction host with deferred resource settlement. Placement and some income sources remain provisional.
const Allocation = preload("res://resource_allocation.gd")
const ResourceSchedule = preload("res://resource_schedule.gd")
const Upkeep = preload("res://upkeep_gate.gd")
const ExtractorYield = preload("res://extractor_yield.gd")
const FootprintOrigin = preload("res://footprint_origin.gd")
const Wind = preload("res://wind_state.gd")
const Renewable = preload("res://renewable_energy.gd")
var game_random := Wind.new()
var wind_state: Dictionary = {}
var tidal_strength := 0.0
var wind_minimum := 100
var wind_maximum := 2000
var terrain_metal := PackedByteArray()
var resource_deadline := 0
const BuildMath = preload("res://construction_math.gd")
const VM = preload("res://cob_vm.gd")
const Navigation = preload("res://terrain_navigation.gd")
const BuildingNavigation = preload("res://building_navigation.gd")
const Mobile = preload("res://mobile_unit.gd")
const WorldCollision = preload("res://world_collision.gd")
const FeatureWorld = preload("res://feature_world.gd")
const WeaponQueries = preload("res://weapon_queries.gd")
const PieceOrigin = preload("res://piece_origin.gd")
const BallisticLaunch = preload("res://ballistic_launch.gd")
var collision: RefCounted
# Both faction resource buildings share the healthy Create/Activate/Deactivate lifecycle validated by compare_native_solar.
const RESOURCE_BUILDINGS := ["armsolar", "armmakr", "armmex", "armwin", "armtide", "corsolar", "cormakr", "cormex", "corwin", "cortide"]
# Ground factories and their level-one products are validated by compare_native_factory and compare_native_units.
const GROUND_FACTORIES := ["armvp", "armlab", "corvp", "corlab"]
const SCRIPTED_UNITS = ["armtide", "armwin", "armmex", "armmakr", "armsolar", "corsolar", "cormakr", "cormex", "corwin", "cortide", "armvp", "armlab", "armck", "armpw", "armrock", "armham", "armjeth", "armwar", "armcv", "armfav", "armflash", "armstump", "armsam", "armmlv",
	"corvp", "corlab", "corck", "corak", "corstorm", "corthud", "corcrash", "corcv", "corfav", "corgator", "corraid", "cormist", "corlevlr", "cormlv",
	# Create-only structure lifecycles validated by compare_native_structures.
	"corestor", "cormstor", "cordrag", "cormine1", "cormine2", "cormine3", "cormine4", "cormine5", "cormine6"]
var mobile_units: Dictionary = {}
var external_units: Dictionary = {}
var features: RefCounted
var map_feature_blocking := PackedByteArray()
var blocking_revision := -1
var last_blocking_grid := PackedByteArray()
var navigation_cache: Dictionary = {}
var yard_signature := ""
var scripts: Dictionary = {}
var factories: Dictionary = {}
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
var team_resources: Dictionary = {}
var completed: Array[int] = []
var status := "Idle"
var ticks := 0
var builder_ready := true
var builder_jobs: Dictionary = {}
var reclaim_jobs: Dictionary = {}
var reclaimed: Array = []

# Core coverage is limited to natively verified scripts; unverified Core menu entries stay visible but unbuildable.
static func supported(type: String) -> bool:
	return not type.begins_with("cor") or type in SCRIPTED_UNITS

func can_build(source_id: int) -> bool:
	if not units.has(source_id) or float(units[source_id].remaining) > 0:
		return false
	return source_id == builder_id or (mobile_units.has(source_id) and scripts.has(source_id) and int(catalog.definition(units[source_id].type).get("builder", "0")) != 0)

func _init(source: RefCounted, terrain: RefCounted, commander_position: Vector2, commander := "armcom") -> void:
	catalog = source
	navigation = terrain
	collision = WorldCollision.new(terrain.width, terrain.height)
	features = FeatureWorld.new(terrain.width, terrain.height, source)
	features.heights = terrain.heights
	map_feature_blocking = terrain.features.duplicate()
	navigation_cache[commander] = {"nav": terrain, "terrain": terrain.blocked.duplicate(), "footprint": Vector2i(2, 2)}
	builder_id = add_unit(commander, commander_position, 0.0)

## Commanders are normally scripted by their owner (the viewer's player Commander); computer players run theirs in the world.
const COMMANDERS := ["armcom", "corcom"]

func add_unit(type: String, position: Vector2, remaining: float, team := 0, scripted_commander := false) -> int:
	var id := next_id
	next_id += 1
	var definition: Dictionary = catalog.definition(type)
	units[id] = {"id": id, "team": team, "type": type, "position": position, "remaining": remaining,
		"energy_ledger": empty_ledger(), "metal_ledger": empty_ledger(),
		"health": 1 if remaining > 0 else int(definition.get("maxdamage", "1")), "active": true,
		# Unit+0xf6/+0xf7: current and previous 30-tick health percentage samples, both zero at creation.
		"health_percent": 0, "previous_health_percent": 0}
	# Only these healthy scripts currently have native lifecycle comparisons.
	if type in SCRIPTED_UNITS or (scripted_commander and type in COMMANDERS):
		var vm = VM.new(catalog.load_script(type))
		# COB RAND draws from the shared game RNG; GET_VALUE 4 reads the unit's live health (callback 0x4807ca).
		vm.rng = game_random
		vm.read_values = {4: VM.health_read(int(units[id].health), int(definition.get("maxdamage", "1"))), 17: ceili(remaining * 100)}
		if type in RESOURCE_BUILDINGS:
			vm.writable_values.assign([1, 5, 20])
		elif type in GROUND_FACTORIES:
			vm.writable_values.assign([5, 18, 19])
			vm.readback_values.assign([18])
			factories[id] = {"queue": [], "product": 0, "opening": false, "status": "Idle"}
		vm.invoke("Create")
		if remaining == 0 and type in RESOURCE_BUILDINGS:
			vm.invoke("Activate")
		scripts[id] = vm
		capture_launch_offset(id)
	refresh_extractor(id)
	collision.sync_unit(self, id)
	return id

## Map features from the prepared placements (names, anchors). Their blocking is already in the base navigation grid.
func load_map_features(placements: Array, voids: Array = []) -> int:
	# Loader pass 1 (0x483aca): void attribute cells hold code 0xfffc before any feature is placed.
	for cell in voids:
		features.codes[int(cell)] = FeatureWorld.VOID
	var placed := 0
	for placement: Dictionary in placements:
		if placement.has("name") and features.place(str(placement.name), int(placement.x), int(placement.z), null, 10) >= 0:
			placed += 1
	blocking_revision = features.revision
	last_blocking_grid = features.blocking_grid(map_feature_blocking)
	return placed

## Rebuild every cached navigation grid when a blocking wreck appears or disappears.
func refresh_feature_blocking() -> void:
	if blocking_revision == features.revision:
		return
	blocking_revision = features.revision
	var grid: PackedByteArray = features.blocking_grid(map_feature_blocking)
	# Replacements that keep the same blocking cells (heaps over heaps, smudges) need no navigation rebuild.
	if grid == last_blocking_grid:
		return
	last_blocking_grid = grid
	var rebuilt: Array = []
	for entry: Dictionary in navigation_cache.values():
		if not rebuilt.has(entry.nav):
			entry.nav.rebuild(grid)
			rebuilt.append(entry.nav)
		entry.terrain = entry.nav.blocked.duplicate()
	if not rebuilt.has(navigation):
		navigation.rebuild(grid)
	refresh_navigation(true)

## Weapon initialization 0x49e070: muzzle/AimFrom Z separation at creation pose and default heading 32768.
func capture_launch_offset(id: int) -> void:
	var type: String = units[id].type
	if str(catalog.definition(type).get("weapon1", "")).is_empty() or not scripts.has(id):
		return
	var vm = scripts[id]
	var queries := WeaponQueries.new(vm)
	var muzzle_name := queries.piece_name(false)
	var aim_name := queries.piece_name(true)
	if queries.fault.is_empty():
		var model: Dictionary = catalog.load_unit(type).model
		var muzzle := PieceOrigin.model_origin(model, vm.pieces, muzzle_name, [0, 32768, 0])
		var aim := PieceOrigin.model_origin(model, vm.pieces, aim_name, [0, 32768, 0])
		units[id].weapon_launch_offset = BallisticLaunch.initial_offset(int(muzzle[2]), int(aim[2]))

## Register a script and movement controller stepped by their owner (the viewer's Commander) so combat,
## targeting and orders can use them; the world does not step external entries itself.
func attach_external(id: int, vm: RefCounted, mobile: RefCounted) -> void:
	scripts[id] = vm
	vm.rng = game_random
	mobile_units[id] = mobile
	external_units[id] = true
	capture_launch_offset(id)

func set_active(id: int, active: bool) -> bool:
	if not scripts.has(id) or units[id].type not in RESOURCE_BUILDINGS or float(units[id].remaining) > 0:
		return false
	if bool(units[id].active) != active:
		units[id].active = active
		scripts[id].invoke("Activate" if active else "Deactivate")
	return true

func remove_unit(id: int) -> void:
	if not units.has(id):
		return
	collision.remove_unit(id)
	stop_build(id)
	if task_id == id or builder_id == id:
		task_id = 0
	for source: int in builder_jobs.keys():
		if int(builder_jobs[source].target) == id:
			stop_build(source)
	for factory: Dictionary in factories.values():
		if int(factory.product) == id:
			factory.product = 0
	factories.erase(id)
	mobile_units.erase(id)
	external_units.erase(id)
	scripts.erase(id)
	units.erase(id)
	refresh_navigation(true)

func queue_unit(factory_id: int, type: String) -> bool:
	if not factories.has(factory_id) or float(units[factory_id].remaining) > 0:
		status = "Finish the factory first"
		return false
	if type not in catalog.build_options(units[factory_id].type) or int(catalog.definition(type).get("buildtime", "0")) <= 0:
		status = "Factory cannot build that unit"
		return false
	if not supported(type):
		status = "Not yet verified for Core"
		return false
	factories[factory_id].queue.append(type)
	factories[factory_id].status = "Queued " + catalog.definition(type).get("name", type)
	return true

func refresh_navigation(force := false) -> void:
	var signature := ""
	for unit: Dictionary in units.values():
		if int(catalog.definition(unit.type).get("bmcode", "1")) == 0:
			signature += "%d:%d:%d;" % [unit.id, int(float(unit.remaining) == 0), int(scripts[unit.id].values.get(18, 0)) if scripts.has(unit.id) else 0]
	if signature == yard_signature and not force:
		return
	yard_signature = signature
	for entry: Dictionary in navigation_cache.values():
		BuildingNavigation.overlay(entry.nav, entry.terrain, units, catalog, scripts, entry.footprint)

func unit_navigation(type: String) -> RefCounted:
	if not navigation_cache.has(type):
		var fields: Dictionary = catalog.movement(type)
		var size := Vector2i(int(fields.get("footprintx", "2")), int(fields.get("footprintz", "2")))
		var nav = Navigation.new(navigation.width, navigation.height, navigation.heights, navigation.sea_level,
			int(fields.get("maxslope", "255")), int(fields.get("maxwaterdepth", "10000")), size,
			int(fields.get("minwaterdepth", "-10000")), int(fields.get("maxwaterslope", "255")), navigation.features)
		navigation_cache[type] = {"nav": nav, "terrain": nav.blocked.duplicate(), "footprint": size}
		refresh_navigation(true)
	return navigation_cache[type].nav

func move_unit(id: int, point: Vector2) -> bool:
	if not mobile_units.has(id) or not mobile_units[id].move_to(point):
		return false
	stop_build(id)
	return true

func clear_factory_queue(factory_id: int) -> void:
	if factories.has(factory_id):
		# Keep the current paid-for unit; clear only orders that have not started.
		factories[factory_id].queue.clear()

func factory_build_position(id: int) -> Vector2:
	var vm = scripts[id]
	var dropped_before: int = vm.dropped_calls
	var query: int = vm.invoke("QueryBuildInfo", [0])
	var index := 0
	if vm.completions.has(query):
		index = int(vm.completions[query].locals[0])
	elif query != -1 or vm.dropped_calls == dropped_before:
		return Vector2(INF, INF)
	# A query dropped because all eight slots are busy keeps its initial value (0x4b0c40), so the pad is piece 0.
	if index < 0 or index >= vm.pieces.size():
		return Vector2(INF, INF)
	var name: String = vm.pieces[index].name
	var model: Dictionary = catalog.load_unit(units[id].type).model
	for piece: Dictionary in model.pieces:
		if piece.name == name:
			# Both enabled factories have the queried pad directly under an unrotated base.
			var offset: Array = piece.offset
			var motion: Array = vm.pieces[index].position
			return units[id].position + Vector2(float(offset[0]) + float(motion[0]), -float(offset[2]) - float(motion[2])) / 65536.0
	return Vector2(INF, INF)

func release_product(factory_id: int, product: int) -> void:
	if mobile_units.has(product):
		return
	var type: String = units[product].type
	if int(catalog.definition(type).get("bmcode", "0")) != 1:
		return
	scripts[factory_id].invoke("StopBuilding")
	mobile_units[product] = Mobile.new(unit_navigation(type), catalog.definition(type), units[product].position, scripts.get(product))
	# Provisional orientation/rally policy for the two unrotated ground factories.
	mobile_units[product].heading = 32768
	var bounds := footprint(units[factory_id].type, units[factory_id].position)
	mobile_units[product].move_to(Vector2(units[factory_id].position.x, bounds.end.y + 64))

func step_factories() -> void:
	for id: int in factories:
		var factory: Dictionary = factories[id]
		if float(units[id].remaining) > 0:
			continue
		var vm = scripts[id]
		if not vm.fault.is_empty():
			factory.status = "Script fault: " + vm.fault
			continue
		var product := int(factory.product)
		if product != 0 and float(units[product].remaining) == 0:
			release_product(id, product)
			if footprint(units[id].type, units[id].position).intersects(footprint(units[product].type, units[product].position)):
				factory.status = "Waiting for completed unit to leave"
				continue
			factory.product = 0
			product = 0
		if product == 0 and factory.queue.is_empty():
			if factory.opening:
				vm.invoke("Deactivate")
				factory.opening = false
			factory.status = "Idle"
			continue
		if not factory.opening:
			vm.invoke("Activate")
			factory.opening = true
		if int(vm.values.get(5, 0)) != 1:
			factory.status = "Opening factory"
			continue
		if product == 0:
			if team_unit_count(int(units[id].get("team", 0))) >= unit_limit:
				factory.status = "Unit limit reached"
				continue
			var point := factory_build_position(id)
			if not point.is_finite():
				factory.status = "Factory build-piece query failed"
				continue
			product = add_unit(str(factory.queue.pop_front()), point, 1.0, int(units[id].get("team", 0)))
			units[product]["produced_by"] = id
			factory.product = product
			vm.invoke("StartBuilding")
		if advance_construction(product, id):
			release_product(id, product)
			factory.status = "Waiting for completed unit to leave"
		else:
			factory.status = status

func footprint(type: String, position: Vector2) -> Rect2:
	var definition: Dictionary = catalog.movement(type)
	var size := Vector2(float(definition.get("footprintx", "1")), float(definition.get("footprintz", "1"))) * 16.0
	return Rect2(position - size * 0.5, size)

func in_build_range(type: String, point: Vector2, source_id := 0) -> bool:
	if source_id == 0:
		source_id = builder_id
	var bounds := footprint(type, point)
	var builder: Dictionary = units[source_id]
	var closest: Vector2 = builder.position.clamp(bounds.position, bounds.end)
	var distance := float(catalog.definition(builder.type).get("builddistance", "60"))
	return builder.position.distance_to(closest) <= distance

func placement_error(type: String, point: Vector2, source_id := 0) -> String:
	if source_id == 0:
		source_id = builder_id
	if not can_build(source_id):
		return "Select a completed construction unit"
	if team_unit_count(int(units[source_id].get("team", 0))) >= unit_limit:
		return "Unit limit reached"
	if type not in catalog.build_options(units[source_id].type):
		return "Builder cannot build that unit"
	if not supported(type):
		return "Not yet verified for Core"
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
	var definition: Dictionary = catalog.movement(type)
	if high - low > int(definition.get("maxslope", "255")):
		return "Terrain is too steep"
	# Original movement-definition initializer 0x4402e0 supplies omitted limits.
	if navigation.sea_level - low > int(definition.get("maxwaterdepth", "10000")) or navigation.sea_level - high < int(definition.get("minwaterdepth", "-10000")):
		return "Invalid water depth"
	for unit: Dictionary in units.values():
		if bounds.intersects(footprint(unit.type, unit.position)):
			return "Space occupied"
	if not in_build_range(type, point, source_id):
		return "Move builder closer to build site"
	return ""

func begin_build(type: String, point: Vector2, source_id := 0) -> int:
	if source_id == 0:
		source_id = builder_id
	point = point.snapped(Vector2(16, 16))
	var error := placement_error(type, point, source_id)
	if not error.is_empty():
		status = error
		return 0
	if float(catalog.definition(type).get("buildtime", "0")) <= 0:
		status = "Unit has no valid build time"
		return 0
	var target := add_unit(type, point, 1.0, int(units[source_id].get("team", 0)))
	assign_build(source_id, target)
	status = "Building " + catalog.definition(type).get("name", type)
	return target

func assign_build(source_id: int, target: int) -> void:
	if source_id == builder_id:
		task_id = target
	else:
		stop_build(source_id)
		mobile_units[source_id].stop()
		builder_jobs[source_id] = {"target": target, "started": false, "status": "Waiting for builder to stop"}

## Reclaim order 0x4147b0 state 2: countdown = trunc(30.0 - (metal + energy) * -0.5) from the feature definition.
static func reclaim_countdown(definition: Dictionary) -> int:
	return int(30.0 - (float(definition.get("metal", 0)) + float(definition.get("energy", 0))) * -0.5)

func can_reclaim(source_id: int) -> bool:
	if not units.has(source_id) or float(units[source_id].remaining) > 0 or int(catalog.definition(units[source_id].type).get("canreclamate", "0")) == 0:
		return false
	return source_id == builder_id or (mobile_units.has(source_id) and scripts.has(source_id))

func feature_bounds(anchor: int) -> Rect2:
	var definition: Dictionary = catalog.feature(features.instances[anchor].name)
	return Rect2(Vector2(anchor % features.width, anchor / features.width) * 16.0, Vector2(int(definition.footprintx), int(definition.footprintz)) * 16.0)

## Provisional approach rule: the builder's build distance to the feature footprint, as for construction.
func in_reclaim_range(source_id: int, anchor: int) -> bool:
	var bounds := feature_bounds(anchor)
	var origin: Vector2 = units[source_id].position
	return origin.distance_to(origin.clamp(bounds.position, bounds.end)) <= float(catalog.definition(units[source_id].type).get("builddistance", "60"))

## Order a builder to reclaim the feature covering a map cell (16 units per cell).
func reclaim(source_id: int, cell: int) -> bool:
	if not can_reclaim(source_id):
		status = "Select a completed unit that can reclaim"
		return false
	var anchor: int = features.anchor_of(cell)
	if anchor < 0 or not features.instances.has(anchor):
		status = "Nothing to reclaim there"
		return false
	var name: String = features.instances[anchor].name
	if not bool(catalog.feature(name).get("reclaimable", false)):
		status = "Feature is not reclaimable"
		return false
	stop_build(source_id)
	var mobile = mobile_units.get(source_id)
	if not in_reclaim_range(source_id, anchor):
		var bounds := feature_bounds(anchor)
		var centre := bounds.get_center()
		var direction: Vector2 = (units[source_id].position - centre).normalized()
		var approach: Vector2 = centre + direction * (bounds.size.length() * 0.5 + float(catalog.definition(units[source_id].type).get("builddistance", "60")) * 0.5)
		if mobile == null or not mobile.move_to(mobile.navigation.nearest_open(approach)):
			status = "Cannot reach the feature"
			return false
	elif mobile != null:
		mobile.stop()
	reclaim_jobs[source_id] = {"anchor": anchor, "name": name, "state": 0, "countdown": 0, "wake": 0, "started": false, "status": "Reclaiming"}
	status = "Reclaiming " + name
	return true

func stop_reclaim(source_id: int) -> void:
	if reclaim_jobs.has(source_id):
		if reclaim_jobs[source_id].started and scripts.has(source_id):
			scripts[source_id].invoke("StopBuilding")
		reclaim_jobs.erase(source_id)

## States follow 0x4147b0: approach and aim (0/1), countdown set (2), two-tick sleeps subtracting two (3), completion (4).
func step_reclaimers() -> void:
	for source_id: int in reclaim_jobs.keys():
		var job: Dictionary = reclaim_jobs[source_id]
		var anchor := int(job.anchor)
		if not units.has(source_id) or not features.instances.has(anchor) or str(features.instances[anchor].name) != str(job.name):
			stop_reclaim(source_id)
			continue
		var vm = scripts.get(source_id)
		if vm != null and not vm.fault.is_empty():
			job.status = "Script fault: " + vm.fault
			continue
		var mobile = mobile_units.get(source_id)
		if int(job.state) == 0:
			if not in_reclaim_range(source_id, anchor):
				if mobile == null or mobile.route.is_empty():
					job.status = "Reclaim paused: out of range"
				continue
			if mobile != null and not mobile.route.is_empty():
				mobile.stop()
			if mobile != null and mobile.speed != 0:
				job.status = "Stopping to reclaim"
				continue
			if vm != null:
				var origin: Vector2 = units[source_id].position
				var target := feature_bounds(anchor).get_center()
				var heading := int(mobile.heading) if mobile != null else 0
				vm.invoke("StartBuilding", [roundi(atan2(origin.x - target.x, origin.y - target.y) * 65536.0 / TAU) - heading, 0])
				job.started = true
			job.state = 1
		if int(job.state) == 1:
			if vm != null and int(vm.values.get(5, 0)) != 1:
				job.status = "Preparing construction arm"
				continue
			job.countdown = reclaim_countdown(catalog.feature(str(job.name)))
			job.state = 2
			job.countdown_tick = ticks
			job.status = "Reclaiming"
			continue
		if ticks < int(job.wake):
			continue
		if int(job.state) == 2:
			job.wake = ticks + 2
			job.countdown = int(job.countdown) - 2
			if int(job.countdown) <= 0:
				job.state = 3
			continue
		complete_reclaim(source_id, anchor)

## 0x4237d0: feature energy and metal join the reclaimer's income accumulators, then 0x423550(x, z, 1)
## swaps in featurereclamate. The AI-controller multiplier branch is not applied.
func complete_reclaim(source_id: int, anchor: int) -> void:
	var name: String = features.instances[anchor].name
	var definition: Dictionary = catalog.feature(name)
	var energy_ledger: Dictionary = units[source_id].energy_ledger
	var metal_ledger: Dictionary = units[source_id].metal_ledger
	energy_ledger.income = Upkeep.float32(energy_ledger.income + float(definition.get("energy", 0)))
	metal_ledger.income = Upkeep.float32(metal_ledger.income + float(definition.get("metal", 0)))
	var successor: int = features.replace(anchor, true)
	var duration := ticks - int(reclaim_jobs[source_id].get("countdown_tick", ticks))
	stop_reclaim(source_id)
	refresh_feature_blocking()
	reclaimed.append({"source": source_id, "name": name, "anchor": anchor, "metal": float(definition.get("metal", 0)), "energy": float(definition.get("energy", 0)),
		"successor": features.instances[successor].name if successor >= 0 else "", "tick": ticks,
		"duration": duration})
	status = "Reclaimed " + name

func stop_build(source_id := 0) -> void:
	stop_reclaim(builder_id if source_id == 0 else source_id)
	if source_id == 0 or source_id == builder_id:
		task_id = 0
	elif builder_jobs.has(source_id):
		if builder_jobs[source_id].started:
			scripts[source_id].invoke("StopBuilding")
		builder_jobs.erase(source_id)
	status = "Build paused"

func resume_build(id: int, source_id := 0) -> bool:
	if source_id == 0:
		source_id = builder_id
	if not can_build(source_id):
		return false
	if not units.has(id) or float(units[id].remaining) <= 0:
		return false
	if int(units[id].get("team", 0)) != int(units[source_id].get("team", 0)):
		status = "Cannot build an enemy structure"
		return false
	if not in_build_range(units[id].type, units[id].position, source_id):
		status = "Move builder closer to resume"
		return false
	assign_build(source_id, id)
	status = "Building " + catalog.definition(units[id].type).get("name", units[id].type)
	return true

func step_builders() -> void:
	for source_id: int in builder_jobs.keys():
		var job: Dictionary = builder_jobs[source_id]
		var unit: Dictionary = units[job.target]
		if float(unit.remaining) == 0:
			stop_build(source_id)
			continue
		var vm = scripts[source_id]
		if not vm.fault.is_empty():
			job.status = "Script fault: " + vm.fault
			continue
		if mobile_units[source_id].speed != 0:
			continue
		if not in_build_range(unit.type, unit.position, source_id):
			job.status = "Build paused: out of range"
			continue
		if not job.started:
			var origin: Vector2 = units[source_id].position
			var target: Vector2 = unit.position
			var angle := roundi(atan2(origin.x - target.x, origin.y - target.y) * 65536.0 / TAU) - int(mobile_units[source_id].heading)
			vm.invoke("StartBuilding", [angle, 0])
			job.started = true
		if int(vm.values.get(5, 0)) != 1:
			job.status = "Preparing construction arm"
			continue
		if advance_construction(job.target, source_id):
			stop_build(source_id)
			status = "Construction complete"
		else:
			job.status = status

func step() -> void:
	ticks += 1
	step_wind()
	completed.clear()
	if ticks % 30 == 0:
		sample_health_percent()
	for id: int in scripts:
		# Fed once per tick before scripts run; external (viewer-stepped) scripts read the same unit health.
		scripts[id].read_values[4] = VM.health_read(int(units[id].health), int(catalog.definition(units[id].type).get("maxdamage", "1")))
		if external_units.has(id):
			continue
		scripts[id].read_values[17] = ceili(float(units[id].remaining) * 100)
		scripts[id].step()
	refresh_navigation()
	for id: int in mobile_units:
		if not external_units.has(id):
			mobile_units[id].step()
		units[id].position = mobile_units[id].point()
	collision.sync(self)
	var schedule := ResourceSchedule.poll(ticks - 1, resource_deadline)
	resource_deadline = schedule.deadline
	if schedule.due:
		settle_economy()
	step_factories()
	step_builders()
	step_reclaimers()
	if task_id == 0 or not builder_ready:
		return
	var unit: Dictionary = units[task_id]
	if not in_build_range(unit.type, unit.position):
		status = "Build paused: out of range"
		return
	if advance_construction(task_id, builder_id):
		task_id = 0

## Unit update on game ticks divisible by 30: previous = current; current = (health * 100 as unsigned) / maxdamage, clamped.
func sample_health_percent() -> void:
	for unit: Dictionary in units.values():
		@warning_ignore("integer_division")
		var percent := ((int(unit.health) * 100) & 0xffffffff) / maxi(1, int(catalog.definition(unit.type).get("maxdamage", "1")))
		unit.previous_health_percent = int(unit.get("health_percent", 0))
		unit.health_percent = clampi(percent, 0, 100)

func advance_construction(target_id: int, source_id: int) -> bool:
	if int(units[target_id].get("team", 0)) != int(units[source_id].get("team", 0)):
		status = "Cannot build an enemy structure"
		return false
	var unit: Dictionary = units[target_id]
	if float(unit.remaining) == 0:
		return true
	var builder_fields: Dictionary = catalog.definition(units[source_id].type)
	var fields: Dictionary = catalog.definition(unit.type)
	var input := {"remaining": unit.remaining, "health": unit.health,
		"energy_cost": float(fields.get("buildcostenergy", "0")), "metal_cost": float(fields.get("buildcostmetal", "0")),
		"build_time": int(fields.buildtime), "max_health": int(fields.get("maxdamage", "1")),
		"work": float(builder_fields.get("workertime", "0")) / 30.0, "energy_debt": units[source_id].energy_ledger.debt, "metal_debt": units[source_id].metal_ledger.debt}
	var result := BuildMath.advance(input)
	for resource: String in ["energy", "metal"]:
		var ledger: Dictionary = units[source_id][resource + "_ledger"]
		ledger.requested = Upkeep.float32(ledger.requested + result[resource + "_requested"])
		ledger.accepted = Upkeep.float32(ledger.accepted + result[resource + "_accepted"])
	if not result.accepted:
		status = "Build paused: unpaid resource debt"
	if result.accepted:
		unit.remaining = result.remaining
		unit.health = result.health
		status = "Building %s · %d%%" % [catalog.definition(unit.type).get("name", unit.type), roundi((1.0 - float(unit.remaining)) * 100)]
		if float(unit.remaining) == 0:
			if scripts.has(target_id):
				scripts[target_id].read_values[17] = 0
				if unit.type in RESOURCE_BUILDINGS:
					scripts[target_id].invoke("Activate")
			completed.append(target_id)
			status = "Construction complete"
			return true
	return false

func resources(team: int) -> Dictionary:
	if team == 0:
		var account: Dictionary = team_resources.get(0, {}).duplicate()
		account.merge({"energy": energy, "metal": metal, "energy_storage": energy_storage, "metal_storage": metal_storage}, true)
		return account
	if not team_resources.has(team):
		team_resources[team] = {"energy": 1000.0, "metal": 1000.0, "energy_storage": base_energy_storage, "metal_storage": base_metal_storage}
	return team_resources[team].duplicate()

func store_resources(team: int, account: Dictionary) -> void:
	team_resources[team] = account.duplicate()
	if team == 0:
		energy = float(account.energy)
		metal = float(account.metal)
		energy_storage = float(account.energy_storage)
		metal_storage = float(account.metal_storage)

func team_unit_count(team: int) -> int:
	var count := 0
	for unit: Dictionary in units.values():
		if int(unit.get("team", 0)) == team:
			count += 1
	return count

static func empty_ledger() -> Dictionary:
	return {"income": 0.0, "requested": 0.0, "accepted": 0.0, "debt": 0.0}

func settle_economy() -> void:
	var accounts: Dictionary = {0: resources(0)}
	for team: int in team_resources:
		accounts[team] = resources(team)
	for unit: Dictionary in units.values():
		var team := int(unit.get("team", 0))
		if not accounts.has(team):
			accounts[team] = resources(team)
	for account: Dictionary in accounts.values():
		account.energy_storage = base_energy_storage
		account.metal_storage = base_metal_storage
	for unit: Dictionary in units.values():
		if float(unit.remaining) > 0:
			continue
		var fields: Dictionary = catalog.definition(unit.type)
		var account: Dictionary = accounts[int(unit.get("team", 0))]
		account.energy_storage = Upkeep.float32(account.energy_storage + float(fields.get("energystorage", "0")))
		account.metal_storage = Upkeep.float32(account.metal_storage + float(fields.get("metalstorage", "0")))
		var e: Dictionary = unit.energy_ledger
		var m: Dictionary = unit.metal_ledger
		e.income = Renewable.accumulate(e.income, bool(unit.active), float(fields.get("extractsmetal", "0")), int(fields.get("makesmetal", "0")), float(fields.get("windgenerator", "0")), float(fields.get("tidalgenerator", "0")), float(wind_state.get("ratio", 0.0)), tidal_strength)
		if bool(unit.active):
			var upkeep := float(fields.get("energyuse", "0"))
			if upkeep < 0:
				e.income = Upkeep.float32(e.income - upkeep)
			else:
				var gate := Upkeep.apply(upkeep, e.debt, e.requested, e.accepted)
				e.requested = gate.requested
				e.accepted = gate.accepted
				if gate.productive:
					if float(fields.get("extractsmetal", "0")) > 0:
						m.income = Upkeep.float32(m.income + float(unit.get("extractor_yield", 0.0)))
					else:
						m.income = Upkeep.float32(m.income + (int(fields.get("makesmetal", "0")) & 255))
		e.income = Upkeep.float32(e.income + float(fields.get("energymake", "0")))
		m.income = Upkeep.float32(m.income + float(fields.get("metalmake", "0")))
	for team: int in accounts:
		var account: Dictionary = accounts[team]
		for resource: String in ["energy", "metal"]:
			var ids: Array[int] = []
			var ledgers: Array = []
			for id: int in units:
				if int(units[id].get("team", 0)) == team:
					ids.append(id)
					ledgers.append(units[id][resource + "_ledger"])
			var result := Allocation.settle_account(account[resource], account[resource + "_storage"], ledgers)
			account[resource] = result.stock
			account[resource + "_income"] = result.income
			account[resource + "_requested"] = result.requested
			account[resource + "_debt"] = 0.0
			for i in range(ids.size()):
				units[ids[i]][resource + "_ledger"] = result.ledgers[i]
				account[resource + "_debt"] = Upkeep.float32(account[resource + "_debt"] + result.ledgers[i].debt)
		store_resources(team, account)

func set_terrain_metal(data: PackedByteArray) -> bool:
	if data.size() != navigation.width * navigation.height:
		return false
	terrain_metal = data.duplicate()
	for id: int in units:
		refresh_extractor(id)
	return true

func refresh_extractor(id: int) -> void:
	var unit: Dictionary = units[id]
	var scale := float(catalog.definition(unit.type).get("extractsmetal", "0"))
	if scale <= 0 or terrain_metal.is_empty():
		return
	var bounds := footprint(unit.type, unit.position)
	var size := Vector2i(bounds.size / 16.0)
	var cells := Rect2i(Vector2i(FootprintOrigin.axis(roundi(unit.position.x * 65536.0), size.x), FootprintOrigin.axis(roundi(unit.position.y * 65536.0), size.y)), size)
	unit.extractor_yield = ExtractorYield.calculate(terrain_metal, navigation.width, navigation.height, cells, scale)
	if scripts.has(id):
		var speed := int(ExtractorYield.calculate(terrain_metal, navigation.width, navigation.height, cells, 1.0))
		scripts[id].invoke("SetSpeed", [speed])

func configure_wind(minimum: int, maximum: int) -> void:
	wind_minimum = minimum
	wind_maximum = maximum
	wind_state = {"next_tick": 0, "strength": 0, "heading": 0, "drift": [0, 0, 0], "ratio": 0.0, "crt_seed": 1, "game_seed": game_random.game_seed}

func step_wind() -> void:
	if wind_state.is_empty():
		return
	var input := wind_state.duplicate(true)
	input.merge({"tick": ticks - 1, "minimum": wind_minimum, "maximum": wind_maximum, "normalization": 5000, "game_seed": game_random.game_seed}, true)
	wind_state = game_random.advance(input)
	game_random.game_seed = wind_state.game_seed
	if wind_state.changed:
		for id: int in scripts:
			if float(catalog.definition(units[id].type).get("windgenerator", "0")) > 0:
				scripts[id].invoke("SetDirection", [wind_state.heading])
				scripts[id].invoke("SetSpeed", [int(wind_state.strength) << 4])
