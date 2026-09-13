extends RefCounted
## Initial EMG combat host. See analysis/COMBAT.md for provisional simulation rules.
const Cycle = preload("res://weapon_cycle.gd")
const Origin = preload("res://piece_origin.gd")
const Damage = preload("res://weapon_damage.gd")
const Aim = preload("res://ballistic_aim.gd")
const Launch = preload("res://ballistic_launch.gd")
const Motion = preload("res://ballistic_motion.gd")
const Splash = preload("res://splash_damage.gd")
const Mobile = preload("res://mobile_unit.gd")
const TargetPoint = preload("res://target_point.gd")
const Queries = preload("res://weapon_queries.gd")
const Burst = preload("res://burst_schedule.gd")
const GameRandom = preload("res://wind_state.gd")
const Reload = preload("res://weapon_reload.gd")
const Ground = preload("res://ground_motion.gd")
const DirectLaunch = preload("res://direct_launch.gd")
var burst_random := GameRandom.new()
var bursts: Array = []
const SUPPORTED_UNITS = ["armflash", "corraid", "armstump", "armham"]
var launch := Launch.new()
var gravity := 8155
var tick := 0
var world: RefCounted
var orders: Dictionary = {}
var cycles: Dictionary = {}
var launch_offsets: Dictionary = {}
var guards: Dictionary = {}
var projectiles: Array = []
var effects: Array = []
var destroyed: Array[int] = []
var shots_fired := 0
var hits := 0
var status := ""

func _init(source: RefCounted) -> void:
	world = source

func stop(id: int, stop_movement := true) -> void:
	if stop_movement and orders.has(id) and orders[id].get("chasing", false) and world.mobile_units.has(id):
		world.mobile_units[id].stop()
	orders.erase(id)
	if cycles.has(id):
		cycles[id].stop()

func enable_guard(id: int) -> bool:
	if not world.units.has(id) or world.units[id].type not in SUPPORTED_UNITS or float(world.units[id].remaining) > 0:
		return false
	guards[id] = tick
	return true

func step_guards() -> void:
	for id: int in guards.keys():
		if not world.units.has(id):
			guards.erase(id)
			stop(id)
			cycles.erase(id)
			launch_offsets.erase(id)
			continue
		if tick < int(guards[id]):
			continue
		guards[id] = tick + 15
		var unit: Dictionary = world.units[id]
		var radius := float(world.catalog.definition(unit.type).get("sightdistance", "0"))
		if orders.has(id):
			var previous := int(orders[id].target)
			if world.units.has(previous) and world.units[previous].get("team", 0) != unit.get("team", 0) and unit.position.distance_to(world.units[previous].position) <= radius:
				continue
			stop(id)
		var chosen := 0
		var nearest := radius * radius
		for candidate: int in world.units:
			var target: Dictionary = world.units[candidate]
			if target.get("team", 0) == unit.get("team", 0):
				continue
			var distance: float = unit.position.distance_squared_to(target.position)
			if distance <= nearest and (chosen == 0 or distance < nearest or candidate < chosen):
				chosen = candidate
				nearest = distance
		if chosen != 0:
			attack(id, chosen, true)

func attack(source: int, target: int, pursue := false) -> bool:
	if not world.units.has(source) or not world.units.has(target) or source == target:
		return false
	if world.units[source].type not in SUPPORTED_UNITS or float(world.units[source].remaining) > 0:
		status = "Combat currently supports completed Flash, Stumpy, Raider and Hammer units"
		return false
	if world.units[source].get("team", 0) == world.units[target].get("team", 0):
		status = "Select an enemy target"
		return false
	if not cycles.has(source):
		cycles[source] = Cycle.new(world.scripts[source], world.catalog.weapon(str(world.catalog.definition(world.units[source].type).weapon1)))
	if not world.mobile_units.has(source):
		world.mobile_units[source] = Mobile.new(world.unit_navigation(world.units[source].type), world.catalog.definition(world.units[source].type), world.units[source].position, world.scripts[source])
		world.mobile_units[source].heading = 32768
	if not launch_offsets.has(source):
		var query = cycles[source].queries
		var muzzle_piece: String = query.piece_name(false)
		var aim_piece: String = query.piece_name(true)
		launch_offsets[source] = int(world.units[source].get("weapon_launch_offset", Launch.initial_offset(raw_point(muzzle(source, muzzle_piece))[2], raw_point(muzzle(source, aim_piece))[2])))
	world.mobile_units[source].stop()
	orders[source] = {"target": target, "heading": -999999, "pitch": -999999,
		"pursue": pursue, "chasing": false, "next_path": 0}
	status = "Attacking target"
	return true

func center(id: int) -> Vector3:
	var unit: Dictionary = world.units[id]
	if world.scripts.has(id):
		var vm = world.scripts[id]
		var query := Queries.new(vm)
		var piece := query.output("SweetSpot", 0)
		var model: Dictionary = world.catalog.load_unit(unit.type).model
		var names: Array = []
		for pose: Dictionary in vm.pieces:
			names.append(str(pose.name).to_lower())
		for item: Dictionary in model.pieces:
			if str(item.name).to_lower() not in names:
				names.append(str(item.name).to_lower())
		if query.fault.is_empty() and piece >= 0 and piece < names.size():
			var heading := int(world.mobile_units[id].heading) if world.mobile_units.has(id) else 32768
			var position := raw_point(Vector3(unit.position.x, world.navigation.height_at(unit.position), unit.position.y))
			return render_point(TargetPoint.model_point(model, vm.pieces, names[piece], [0, heading, 0], position))
	var height := 12.0
	if world.collision.records.has(id):
		height = float(world.collision.records[id].bounds.upper[1]) / 131072.0
	return Vector3(unit.position.x, world.navigation.height_at(unit.position) + height, unit.position.y)

func muzzle(source: int, piece: String) -> Vector3:
	var unit: Dictionary = world.units[source]
	var model: Dictionary = world.catalog.load_unit(unit.type).model
	var raw := Origin.model_origin(model, world.scripts[source].pieces, piece, [0, int(world.mobile_units[source].heading), 0])
	return Vector3(unit.position.x, world.navigation.height_at(unit.position), unit.position.y) + render_point(raw)

static func raw_point(point: Vector3) -> Array:
	return [roundi(point.x * 65536.0), roundi(point.y * 65536.0), roundi(point.z * 65536.0)]

static func render_point(raw: Array) -> Vector3:
	return Vector3(float(raw[0]) / 65536.0, float(raw[1]) / 65536.0, float(raw[2]) / 65536.0)

func step() -> void:
	tick += 1
	var burst_copies := advance_bursts()
	step_guards()
	destroyed.clear()
	for effect: Dictionary in effects:
		effect.life -= 1
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.life > 0)
	for source: int in orders.keys():
		if not world.units.has(source) or not world.units.has(orders[source].target):
			stop(source)
			continue
		var order: Dictionary = orders[source]
		var target := int(order.target)
		var origin: Vector2 = world.units[source].position
		var destination: Vector2 = world.units[target].position
		var cycle = cycles[source]
		var aim_piece: String = cycle.queries.piece_name(true)
		if aim_piece.is_empty():
			status = cycle.queries.fault
			stop(source)
			continue
		var aim_origin := muzzle(source, aim_piece)
		var target_point := center(target)
		var heading := roundi(atan2(aim_origin.x - target_point.x, aim_origin.z - target_point.z) * 65536.0 / TAU) - int(world.mobile_units[source].heading)
		var within_range := origin.distance_to(destination) <= float(cycle.definition.get("range", "0"))
		if order.pursue:
			if not within_range and tick >= int(order.next_path):
				var approach: Vector2 = destination + (origin - destination).normalized() * float(cycle.definition.range) * 0.85
				order.chasing = world.mobile_units[source].move_to(approach)
				if not order.chasing:
					world.mobile_units[source].stop()
				order.next_path = tick + 30
			elif within_range and order.chasing:
				world.mobile_units[source].stop()
				order.chasing = false
		var ballistic := int(cycle.definition.get("ballistic", "0")) != 0
		var pitch := Aim.solve(raw_point(aim_origin - target_point), int(cycle.runtime.velocity_raw_per_tick), gravity, float(cycle.runtime.minimum_barrel_angle)) if ballistic else 0
		within_range = within_range and pitch != 0x8000
		if cycle.aim_id < 0 and (not cycle.requested or heading != int(order.heading) or pitch != int(order.pitch)):
			cycle.aim(heading, pitch)
			order.heading = heading
			order.pitch = pitch
		var unit: Dictionary = world.units[source]
		var reload_delay := Reload.ticks(int(cycle.runtime.reload_ticks), int(unit.health), int(world.catalog.definition(unit.type).maxdamage), int(unit.get("experience", 0)))
		cycle.step(within_range and world.mobile_units[source].speed == 0, func(piece: String) -> Vector3: return muzzle(source, piece), reload_delay, tick)
		if not cycle.fault.is_empty():
			status = cycle.fault
			stop(source)
			continue
		for shot: Dictionary in cycle.shots:
			var start: Vector3 = shot.position
			if ballistic:
				var speed := int(shot.velocity_raw_per_tick)
				var raw := raw_point(start)
				var timer := int(float(cycle.definition.get("weapontimer", "0")) * 30.0) & 65535
				var burn := int(cycle.definition.get("burnblow", "0")) != 0
				var world_heading := heading + int(world.mobile_units[source].heading)
				projectiles.append({"source": source, "owner": int(world.units[source].get("team", 0)),
					"position": start, "previous": start, "position_raw": raw,
					"velocity_raw": launch.velocity(world_heading, pitch, speed, gravity, int(launch_offsets[source])),
					"ballistic": true, "timer": timer, "burnblow": burn,
					"deadline": Launch.deadline(tick, timer, burn, raw, raw_point(center(target)), launch.trig.velocity_component(pitch, speed, 16384)),
					"area": int(cycle.definition.get("areaofeffect", "0")), "edge": float(cycle.definition.get("edgeeffectiveness", "0")),
					"damage": cycle.definition.get("damage", {})})
				shots_fired += 1
				continue
			var direct := DirectLaunch.solve(raw_point(start), raw_point(center(target)), int(shot.velocity_raw_per_tick))
			var velocity_raw: Array = direct.velocity
			var projectile := {"source": source, "owner": int(world.units[source].get("team", 0)), "position": start, "previous": start,
				"position_raw": raw_point(start), "velocity_raw": velocity_raw,
				"distance": 0.0, "range": float(cycle.definition.range), "damage": cycle.definition.get("damage", {"default": "8"})}
			if int(shot.burst) > 0:
				bursts.append({"source": source, "piece_name": shot.piece_name, "projectile": projectile,
					"interval": int(cycle.runtime.burst_interval_ticks), "timer": int(float(cycle.definition.get("weapontimer", "0")) * 30),
					"speed": int(shot.velocity_raw_per_tick), "distance": int(direct.distance), "spray": int(cycle.definition.get("sprayangle", "0")),
					"state": {"position": raw_point(start), "velocity": velocity_raw, "remaining": int(shot.burst), "timestamp": tick, "deadline": 0, "removed": false,
						"heading": int(direct.heading), "pitch": int(direct.pitch)}})
			else:
				projectiles.append(projectile)
				shots_fired += 1
	var survivors: Array = []
	for projectile: Dictionary in projectiles:
		if projectile.get("ballistic", false):
			if step_shell(projectile):
				survivors.append(projectile)
			continue
		var start: Vector3 = projectile.position
		if projectile.has("deadline") and (tick & 0xffffffff) >= (int(projectile.deadline) & 0xffffffff):
			continue
		var velocity := render_point(projectile.velocity_raw)
		var travel := velocity.length() if projectile.has("deadline") else minf(velocity.length(), maxf(0, float(projectile.range) - float(projectile.distance)))
		if travel <= 0:
			continue
		var fraction := travel / velocity.length()
		var next_raw: Array = projectile.position_raw.duplicate()
		for axis in range(3):
			next_raw[axis] = Ground.signed32(int(next_raw[axis]) + int(int(projectile.velocity_raw[axis]) * fraction))
		var end := render_point(next_raw)
		if world.collision.projectile_cell(next_raw) < 0:
			continue
		var target: int = world.collision.target_at(world, next_raw, int(projectile.owner))
		if target != 0:
			var damage := Damage.amount(Damage.base_damage(projectile.damage, world.units[target].type), 1.0)
			world.units[target].health = maxi(0, int(world.units[target].health) - damage)
			hits += 1
			effects.append({"position": end, "life": 8})
			if int(world.units[target].health) == 0:
				destroyed.append(target)
				world.remove_unit(target)
				stop(target)
				cycles.erase(target)
				launch_offsets.erase(target)
			continue
		projectile.previous = start
		projectile.position = end
		projectile.position_raw = next_raw
		projectile.distance += travel
		if (projectile.has("deadline") or float(projectile.distance) < float(projectile.range)) and end.y >= world.navigation.height_at(Vector2(end.x, end.z)):
			survivors.append(projectile)
	projectiles = survivors
	# Native updater snapshots its pool size: newly copied rounds move next tick.
	projectiles.append_array(burst_copies)

func advance_bursts() -> Array:
	var copies: Array = []
	var pending: Array = []
	for burst: Dictionary in bursts:
		# Native death cleanup removes burst sources, not already-emitted rounds.
		# Remove all here; do not preserve the native adjacent-compaction skip.
		if not world.units.has(burst.source) or not world.scripts.has(burst.source):
			continue
		var fresh := raw_point(muzzle(int(burst.source), str(burst.piece_name)))
		var result := Burst.advance(burst.state, tick, int(burst.interval), int(burst.timer), int(burst.speed), int(burst.distance), fresh)
		burst.state = result.source
		if result.copy != null:
			var projectile: Dictionary = burst.projectile.duplicate(true)
			projectile.position_raw = result.copy.position
			projectile.position = render_point(result.copy.position)
			projectile.previous = projectile.position
			projectile.velocity_raw = result.copy.velocity
			projectile.deadline = int(result.copy.deadline)
			copies.append(projectile)
			shots_fired += 1
			if int(burst.spray) != 0:
				Burst.apply_spread(burst.state, int(burst.speed), int(burst.spray), burst_random.bounded_random(int(burst.spray)))
		if not burst.state.removed:
			pending.append(burst)
	bursts = pending
	return copies

func step_shell(projectile: Dictionary) -> bool:
	var expired := Motion.expiration(tick, int(projectile.deadline), int(projectile.timer), projectile.burnblow)
	if expired != 0:
		if expired == 2:
			blast(projectile)
		return false
	var next := Motion.integrate(projectile.position_raw, projectile.velocity_raw, gravity, [0, 0, 0])
	projectile.previous = projectile.position
	projectile.position_raw = next.position
	projectile.velocity_raw = next.velocity
	projectile.position = render_point(next.position)
	if world.collision.projectile_cell(next.position) < 0:
		return false
	var target: int = world.collision.target_at(world, next.position, int(projectile.owner))
	if target != 0 or projectile.position.y < world.navigation.height_at(Vector2(projectile.position.x, projectile.position.z)):
		blast(projectile)
		return false
	return true

func blast(projectile: Dictionary) -> void:
	effects.append({"position": projectile.position, "life": 8})
	@warning_ignore("integer_division")
	var radius: int = int(projectile.area) / 2
	for id: int in world.collision.records.keys():
		if id == int(projectile.source):
			continue
		var record: Dictionary = world.collision.records[id]
		var multiplier := Splash.multiplier(projectile.position_raw, record.position_raw, record.bounds.lower, record.bounds.upper, radius, float(projectile.edge))
		if multiplier <= 0:
			continue
		var damage := Damage.amount(Damage.base_damage(projectile.damage, world.units[id].type), multiplier)
		world.units[id].health = maxi(0, int(world.units[id].health) - damage)
		hits += 1
		if int(world.units[id].health) == 0:
			destroyed.append(id)
			world.remove_unit(id)
			stop(id)
			cycles.erase(id)
			launch_offsets.erase(id)
