extends RefCounted
signal sound_requested(name: String, position: Vector3)
## Initial EMG combat host. See analysis/COMBAT.md for provisional simulation rules.
const Cycle = preload("res://weapon_cycle.gd")
const Origin = preload("res://piece_origin.gd")
const Damage = preload("res://weapon_damage.gd")
const Aim = preload("res://ballistic_aim.gd")
const Launch = preload("res://ballistic_launch.gd")
const Motion = preload("res://ballistic_motion.gd")
const Splash = preload("res://splash_damage.gd")
const FeatureDamage = preload("res://feature_damage.gd")
const DamageNotify = preload("res://damage_notify.gd")
## Weapon-hit script notifications issued: {id, tick, hit [cos, sin], percent}.
var notifications: Array = []
## Game option word +0x37f2f as initialized at 0x430e84/0x430e90; bit 8 enables feature damage.
const GAME_FLAGS := 0xc
var feature_destructions := 0
var feature_ignitions: Array = []
const Mobile = preload("res://mobile_unit.gd")
const TargetPoint = preload("res://target_point.gd")
const Queries = preload("res://weapon_queries.gd")
const Burst = preload("res://burst_schedule.gd")
const GameRandom = preload("res://wind_state.gd")
const Reload = preload("res://weapon_reload.gd")
const Ground = preload("res://ground_motion.gd")
const DirectDeadline = preload("res://direct_deadline.gd")
const GuidedMotion = preload("res://guided_motion.gd")
const MissileTarget = preload("res://missile_target.gd")
const RocketMotion = preload("res://rocket_motion.gd")
const DirectLaunch = preload("res://direct_launch.gd")
const BeamMotion = preload("res://beam_motion.gd")
var burst_random := GameRandom.new()
var bursts: Array = []
const SUPPORTED_UNITS = ["armflash", "corraid", "armstump", "armham", "armpw", "armrock", "armwar", "armsam", "armjeth",
	# Core counterparts use the same cannon, rocket and guided-missile hosts.
	"corthud", "corlevlr", "corstorm", "cormist", "corcrash",
	# Beam lasers (weapon flag 0x8) use the native-compared tail update in beam_motion.gd.
	"armfav", "corfav", "corgator", "corak",
	# Commander primary beam lasers (the D-gun command-fire weapon is not yet connected).
	"armcom", "corcom"]
var launch := Launch.new()
var gravity := 8155
var tick := 0
var world: RefCounted
var orders: Dictionary = {}
var cycles: Dictionary = {}
var launch_offsets: Dictionary = {}
var guards: Dictionary = {}
var guard_pursuit: Dictionary = {}
## Command-fire (D-gun) orders use weapon slot 3 with their own script cycle.
var command_orders: Dictionary = {}
var command_cycles: Dictionary = {}
var pending_deaths: Array = []
## Processed deaths: unit type, severity, Killed corpse type, corpse feature name, position and debris explosions.
var deaths: Array = []
var projectiles: Array = []
var effects: Array = []
const EffectAssets = preload("res://weapon_effects.gd")
var effect_assets := EffectAssets.new(ProjectSettings.globalize_path("res://../local/weapon-effects/"))
var destroyed: Array[int] = []
var shots_fired := 0
var hits := 0
var status := ""

func _init(source: RefCounted) -> void:
	world = source
	burst_random = world.game_random

func stop(id: int, stop_movement := true) -> void:
	for active: Dictionary in [orders, command_orders]:
		if stop_movement and active.has(id) and active[id].get("chasing", false) and world.mobile_units.has(id):
			world.mobile_units[id].stop()
	orders.erase(id)
	command_orders.erase(id)
	if cycles.has(id):
		cycles[id].stop()
	if command_cycles.has(id):
		command_cycles[id].stop()

func end_order(id: int, command: bool) -> void:
	if not command:
		stop(id)
		return
	if command_orders.has(id) and command_orders[id].get("chasing", false) and world.mobile_units.has(id):
		world.mobile_units[id].stop()
	command_orders.erase(id)
	if command_cycles.has(id):
		command_cycles[id].stop()

## Command fire with the unit's weapon3 (Commander D-gun) at an enemy unit; pursues into range and fires once.
func command_fire(source: int, target: int) -> bool:
	if not world.units.has(source) or not world.units.has(target) or source == target:
		return false
	var fields: Dictionary = world.catalog.definition(world.units[source].type)
	var weapon: Dictionary = world.catalog.weapon(str(fields.get("weapon3", "")))
	if weapon.is_empty() or int(weapon.definition.get("commandfire", "0")) & 1 == 0 or not world.scripts.has(source):
		status = "Unit has no command-fire weapon"
		return false
	if world.units[source].get("team", 0) == world.units[target].get("team", 0):
		status = "Select an enemy target"
		return false
	if not command_cycles.has(source):
		command_cycles[source] = Cycle.new(world.scripts[source], weapon, "Tertiary")
	if not command_cycles[source].fault.is_empty():
		status = command_cycles[source].fault
		return false
	if not launch_offsets.has(source):
		launch_offsets[source] = int(world.units[source].get("weapon_launch_offset", 0))
	# The primary attack yields movement control to the command order.
	if orders.has(source):
		stop(source, false)
	command_orders[source] = {"target": target, "heading": -999999, "pitch": -999999, "pursue": true, "chasing": false, "next_path": 0}
	status = "Command fire ordered"
	return true

## Ground attack (the Suppress order 0x4038a0): keep firing the primary weapon at a map point until stopped.
func attack_ground(source: int, point: Vector2) -> bool:
	if not world.units.has(source) or world.units[source].type not in SUPPORTED_UNITS or float(world.units[source].remaining) > 0 or not world.scripts.has(source):
		status = "Select a completed combat unit"
		return false
	if not cycles.has(source):
		cycles[source] = Cycle.new(world.scripts[source], world.catalog.weapon(str(world.catalog.definition(world.units[source].type).weapon1)))
	if not world.mobile_units.has(source):
		world.mobile_units[source] = Mobile.new(world.unit_navigation(world.units[source].type), world.catalog.definition(world.units[source].type), world.units[source].position, world.scripts[source])
		world.mobile_units[source].heading = 32768
	if not launch_offsets.has(source):
		launch_offsets[source] = int(world.units[source].get("weapon_launch_offset", 0))
	orders[source] = ground_order(point, float(cycles[source].definition.get("range", "0")))
	status = "Suppressing fire"
	return true

## Command fire (D-gun, weapon slot 3) at a map point: one shot, then the order completes (event 0x800).
func command_fire_ground(source: int, point: Vector2) -> bool:
	if not world.units.has(source) or not world.scripts.has(source):
		return false
	var weapon: Dictionary = world.catalog.weapon(str(world.catalog.definition(world.units[source].type).get("weapon3", "")))
	if weapon.is_empty() or int(weapon.definition.get("commandfire", "0")) & 1 == 0:
		status = "Unit has no command-fire weapon"
		return false
	if not command_cycles.has(source):
		command_cycles[source] = Cycle.new(world.scripts[source], weapon, "Tertiary")
	if not launch_offsets.has(source):
		launch_offsets[source] = int(world.units[source].get("weapon_launch_offset", 0))
	if orders.has(source):
		stop(source, false)
	command_orders[source] = ground_order(point, float(weapon.definition.get("range", "0")))
	status = "Command fire at ground ordered"
	return true

## Ground orders store the clicked point as integer world X/Z words (0x48a0a0: a Z of 0x8000 becomes 0x8001);
## approach distance R starts at the weapon range.
func ground_order(point: Vector2, weapon_range: float) -> Dictionary:
	var x16 := Ground.signed16(roundi(point.x * 65536.0) >> 16)
	var z16 := Ground.signed16(roundi(point.y * 65536.0) >> 16)
	if z16 == -32768:
		z16 = -32767
	return {"target": 0, "point": [x16, z16], "heading": -999999, "pitch": -999999, "pursue": true, "chasing": false, "next_path": 0,
		"approach": int(weapon_range), "restart": 0}

## 0x48a1e0 point target: (X << 16, max(bilinear terrain height, sea level) << 16 with a strict '>', Z << 16);
## no SweetSpot, height offset or target leading.
static func ground_target(point: Array, heights: PackedByteArray, width: int, rows: int, sea_level: int) -> Array:
	var tx := Ground.signed32(int(point[0]) << 16)
	var tz := Ground.signed32(int(point[1]) << 16)
	var height := FeatureDamage.height(heights, width, rows, tx, tz)
	return [tx, Ground.signed32((height if height > sea_level else sea_level) << 16), tz]

func order_target_point(order: Dictionary) -> Vector3:
	if order.has("point"):
		return render_point(ground_target(order.point, world.navigation.heights, world.navigation.width, world.navigation.height, int(world.navigation.sea_level)))
	return center(int(order.target))

func shot_affordable(source: int, definition: Dictionary) -> bool:
	var energy := float(definition.get("energypershot", "0"))
	var metal := float(definition.get("metalpershot", "0"))
	if energy <= 0 and metal <= 0:
		return true
	var account: Dictionary = world.resources(int(world.units[source].get("team", 0)))
	return energy <= float(account.energy) and metal <= float(account.metal)

## 0x4012a0: subtract per-shot cost from stock immediately and add it to the unit's requested totals.
func pay_shot(source: int, definition: Dictionary) -> void:
	var energy := float(definition.get("energypershot", "0"))
	var metal := float(definition.get("metalpershot", "0"))
	if energy <= 0 and metal <= 0:
		return
	var team := int(world.units[source].get("team", 0))
	var account: Dictionary = world.resources(team)
	if energy > float(account.energy) or metal > float(account.metal):
		return
	account.energy = float(account.energy) - energy
	world.units[source].energy_ledger.requested = float(world.units[source].energy_ledger.requested) + energy
	if metal <= float(account.metal):
		account.metal = float(account.metal) - metal
		world.units[source].metal_ledger.requested = float(world.units[source].metal_ledger.requested) + metal
	world.store_resources(team, account)

## Automatic target acquisition. Pursuing guards search their sight radius and chase; holding guards only
## engage within weapon range and never stop or move the unit (used for the player-controlled Commander).
func enable_guard(id: int, pursue := true) -> bool:
	if not world.units.has(id) or world.units[id].type not in SUPPORTED_UNITS or float(world.units[id].remaining) > 0:
		return false
	guards[id] = tick
	guard_pursuit[id] = pursue
	return true

func step_guards() -> void:
	for id: int in guards.keys():
		if not world.units.has(id):
			guards.erase(id)
			guard_pursuit.erase(id)
			stop(id)
			cycles.erase(id)
			launch_offsets.erase(id)
			continue
		if tick < int(guards[id]):
			continue
		guards[id] = tick + 15
		var unit: Dictionary = world.units[id]
		var pursue: bool = guard_pursuit.get(id, true)
		var fields: Dictionary = world.catalog.definition(unit.type)
		var radius := float(fields.get("sightdistance", "0"))
		if not pursue:
			radius = minf(radius, float(world.catalog.weapon(str(fields.get("weapon1", ""))).get("definition", {}).get("range", "0")))
		if orders.has(id):
			# Player ground-attack orders are not replaced by automatic targeting.
			if orders[id].has("point"):
				continue
			var previous := int(orders[id].target)
			if world.units.has(previous) and world.units[previous].get("team", 0) != unit.get("team", 0) and unit.position.distance_to(world.units[previous].position) <= radius:
				continue
			# A player-issued pursuit order on a holding guard is left to the player.
			if not pursue and orders[id].pursue:
				continue
			stop(id, pursue)
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
			attack(id, chosen, pursue, pursue)

func attack(source: int, target: int, pursue := false, stop_movement := true) -> bool:
	if not world.units.has(source) or not world.units.has(target) or source == target:
		return false
	if world.units[source].type not in SUPPORTED_UNITS or float(world.units[source].remaining) > 0:
		status = "Combat currently supports completed Flash, Stumpy, Raider, Hammer, Peewee, Rocko, Warrior, Samson, Jethro, Thud, Leveler, Storm, Slasher and Crasher units"
		return false
	if world.units[source].get("team", 0) == world.units[target].get("team", 0):
		status = "Select an enemy target"
		return false
	if not world.scripts.has(source):
		status = "Unit has no running weapon script"
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
	if stop_movement:
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

static func offset_point(base_raw: Array, offset_raw: Array) -> Array:
	return [Ground.signed32(int(base_raw[0]) + int(offset_raw[0])), Ground.signed32(int(base_raw[1]) + int(offset_raw[1])), Ground.signed32(int(base_raw[2]) + int(offset_raw[2]))]

## Relative turret heading and ballistic pitch from an AimFrom point to a target point (raw 16.16).
static func ballistic_angles(aim_raw: Array, target_raw: Array, unit_heading: int, speed: int, gravity: int, minimum_angle: float) -> Array:
	var delta := [int(aim_raw[0]) - int(target_raw[0]), int(aim_raw[1]) - int(target_raw[1]), int(aim_raw[2]) - int(target_raw[2])]
	var heading := roundi(atan2(float(delta[0]), float(delta[2])) * 65536.0 / TAU) - unit_heading
	return [heading, Aim.solve(delta, speed, gravity, minimum_angle)]

## Turret fire callback 0x49d580 spread: damage and accuracy widen, experience narrows, two game-RNG draws.
## Returns the perturbed absolute heading and pitch (16-bit). Direct launchers recompute direction, so only the draws matter there.
static func firing_spread(heading: int, pitch: int, accuracy: int, health: int, maxdamage: int, experience: int, rng: RefCounted) -> Array:
	var health_word := health & 0xffff
	if health_word >= 0x8000:
		health_word -= 0x10000
	var shifted := (health_word << 11) & 0xffffffff
	@warning_ignore("integer_division")
	var damage := (shifted / maxi(1, maxdamage)) & 0xffff
	var spread := ((accuracy & 0xffff) - damage + 0x800) & 0xffff
	# imul by 0x2aaaaaab keeps the high word (/6), then sar 1: experience / 12.
	@warning_ignore("integer_division")
	var divisor := (experience & 0xffff) / 12
	if divisor > 1:
		@warning_ignore("integer_division")
		spread = spread / divisor
	if spread != 0:
		var half := spread >> 1
		heading = (heading + rng.bounded_random(spread) - half) & 0xffff
		pitch = (pitch + rng.bounded_random(spread) - half) & 0xffff
	return [heading & 0xffff, pitch & 0xffff]

static func raw_point(point: Vector3) -> Array:
	return [roundi(point.x * 65536.0), roundi(point.y * 65536.0), roundi(point.z * 65536.0)]

static func render_point(raw: Array) -> Vector3:
	return Vector3(float(raw[0]) / 65536.0, float(raw[1]) / 65536.0, float(raw[2]) / 65536.0)

func step() -> void:
	tick += 1
	step_self_destructs()
	var burst_copies := advance_bursts()
	step_guards()
	destroyed.clear()
	for effect: Dictionary in effects:
		effect.life -= 1
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.life > 0)
	var entries: Array = []
	for source: int in orders.keys():
		entries.append([source, false])
	for source: int in command_orders.keys():
		entries.append([source, true])
	for entry: Array in entries:
		var source: int = entry[0]
		var command: bool = entry[1]
		var active: Dictionary = command_orders if command else orders
		if not active.has(source):
			continue
		if not world.units.has(source) or (not active[source].has("point") and not world.units.has(active[source].target)):
			end_order(source, command)
			continue
		var order: Dictionary = active[source]
		var target := int(order.target)
		var ground: bool = order.has("point")
		var origin: Vector2 = world.units[source].position
		var destination: Vector2 = Vector2(int(order.point[0]), int(order.point[1])) if ground else world.units[target].position
		var cycle = command_cycles[source] if command else cycles[source]
		var aim_piece: String = cycle.queries.piece_name(true)
		if aim_piece.is_empty():
			status = cycle.queries.fault
			end_order(source, command)
			continue
		var aim_origin := muzzle(source, aim_piece)
		var target_point := order_target_point(order)
		var ballistic := int(cycle.definition.get("ballistic", "0")) != 0
		var angles := ballistic_angles(raw_point(aim_origin), raw_point(target_point), int(world.mobile_units[source].heading), int(cycle.runtime.velocity_raw_per_tick), gravity, float(cycle.runtime.minimum_barrel_angle))
		var heading := int(angles[0])
		var within_range := origin.distance_to(destination) <= float(cycle.definition.get("range", "0"))
		if ground:
			step_ground_approach(source, order, origin, destination, within_range, float(cycle.definition.get("range", "0")))
		elif order.pursue:
			if not within_range and tick >= int(order.next_path):
				var approach: Vector2 = destination + (origin - destination).normalized() * float(cycle.definition.range) * 0.85
				order.chasing = world.mobile_units[source].move_to(approach)
				if not order.chasing:
					world.mobile_units[source].stop()
				order.next_path = tick + 30
			elif within_range and order.chasing:
				world.mobile_units[source].stop()
				order.chasing = false
		var pitch := int(angles[1]) if ballistic else 0
		within_range = within_range and pitch != 0x8000
		if cycle.aim_id < 0 and (not cycle.requested or heading != int(order.heading) or pitch != int(order.pitch)):
			cycle.aim(heading, pitch)
			order.heading = heading
			order.pitch = pitch
		var unit: Dictionary = world.units[source]
		var reload_delay := Reload.ticks(int(cycle.runtime.reload_ticks), int(unit.health), int(world.catalog.definition(unit.type).maxdamage), int(unit.get("experience", 0)))
		# 0x49e1a0 fires a non-stockpile weapon only when the owner's stock covers its per-shot energy and metal.
		var affordable := shot_affordable(source, cycle.definition)
		cycle.step(within_range and world.mobile_units[source].speed == 0 and affordable, func(piece: String) -> Vector3: return muzzle(source, piece), reload_delay, tick)
		if not cycle.fault.is_empty():
			status = cycle.fault
			end_order(source, command)
			continue
		var emitted: Array = cycle.shots.duplicate()
		if command and not emitted.is_empty():
			# A command-fire order completes after its shot; stopping the cycle clears its shot list, so use the copy.
			command_orders.erase(source)
			command_cycles[source].stop()
		for shot: Dictionary in emitted:
			var start: Vector3 = shot.position
			pay_shot(source, cycle.definition)
			request_sound(str(cycle.definition.get("soundstart", "")), start)
			var world_heading := (heading + int(world.mobile_units[source].heading)) & 0xffff
			var shot_pitch := pitch & 0xffff
			if int(cycle.definition.get("turret", "0")) & 1:
				var source_unit: Dictionary = world.units[source]
				var spread := firing_spread(world_heading, shot_pitch, int(cycle.definition.get("accuracy", "0")), int(source_unit.health),
					int(world.catalog.definition(source_unit.type).get("maxdamage", "1")), int(source_unit.get("experience", 0)), burst_random)
				world_heading = int(spread[0])
				shot_pitch = int(spread[1])
			if ballistic:
				var speed := int(shot.velocity_raw_per_tick)
				var raw := raw_point(start)
				var timer := int(float(cycle.definition.get("weapontimer", "0")) * 30.0) & 65535
				var burn := int(cycle.definition.get("burnblow", "0")) != 0
				projectiles.append({"source": source, "owner": int(world.units[source].get("team", 0)),
					"position": start, "previous": start, "position_raw": raw,
					"velocity_raw": launch.velocity(world_heading, shot_pitch, speed, gravity, int(launch_offsets[source])),
					"ballistic": true, "timer": timer, "burnblow": burn,
					"deadline": Launch.deadline(tick, timer, burn, raw, raw_point(target_point), launch.trig.velocity_component(shot_pitch, speed, 16384)),
					"area": int(cycle.definition.get("areaofeffect", "0")), "edge": float(cycle.definition.get("edgeeffectiveness", "0")),
					"collision_flags": world.collision.collision_flags(cycle.definition),
					"explosion": str(cycle.definition.get("explosiongaf", "")) + "/" + str(cycle.definition.get("explosionart", "")), "soundhit": str(cycle.definition.get("soundhit", "")), "damage": cycle.definition.get("damage", {}), "firestarter": int(cycle.definition.get("firestarter", "0"))})
				shots_fired += 1
				continue
			var direct := DirectLaunch.solve(raw_point(start), raw_point(target_point), int(shot.velocity_raw_per_tick), int(cycle.runtime.start_velocity_raw_per_tick), int(cycle.runtime.acceleration_raw_per_tick_squared))
			var velocity_raw: Array = direct.velocity
			var projectile := {"source": source, "owner": int(world.units[source].get("team", 0)), "position": start, "previous": start,
				"position_raw": raw_point(start), "velocity_raw": velocity_raw, "collision_flags": world.collision.collision_flags(cycle.definition),
				"explosion": str(cycle.definition.get("explosiongaf", "")) + "/" + str(cycle.definition.get("explosionart", "")), "soundhit": str(cycle.definition.get("soundhit", "")), "distance": 0.0, "range": float(cycle.definition.range), "damage": cycle.definition.get("damage", {"default": "8"}), "firestarter": int(cycle.definition.get("firestarter", "0"))}
			if int(cycle.definition.get("selfprop", "0")) != 0:
				projectile.merge({"rocket": true, "guided": int(cycle.definition.get("guidance", "0")) != 0,
					"target_id": target, "saved_target": raw_point(target_point), "turn": int(cycle.runtime.turn_raw_per_tick), "speed": int(direct.initial_speed),
					"maximum": int(shot.velocity_raw_per_tick), "acceleration": int(cycle.runtime.acceleration_raw_per_tick_squared),
					"heading": int(direct.heading), "pitch": int(direct.pitch),
					"deadline": DirectDeadline.deadline(tick, int(shot.velocity_raw_per_tick), int(cycle.definition.range), int(float(cycle.definition.get("weapontimer", "0")) * 30.0), int(cycle.definition.get("noautorange", "0")) != 0),
					"area": int(cycle.definition.get("areaofeffect", "0")), "edge": float(cycle.definition.get("edgeeffectiveness", "0"))})
				projectiles.append(projectile)
				shots_fired += 1
				continue
			if int(cycle.definition.get("beamweapon", "0")) != 0:
				# Direct launch 0x49c9c0 starts the tail at the muzzle and stamps the launch tick for the duration delay.
				projectile.merge({"beam": true, "tail_raw": raw_point(start), "tail": start, "launch": tick, "released": false,
					"duration": int(cycle.runtime.duration_ticks), "target_id": target,
					"area": int(cycle.definition.get("areaofeffect", "0")), "edge": float(cycle.definition.get("edgeeffectiveness", "0")),
					"noexplode": int(cycle.definition.get("noexplode", "0")) & 1 != 0,
					"deadline": DirectDeadline.deadline(tick, int(shot.velocity_raw_per_tick), int(cycle.definition.range), int(float(cycle.definition.get("weapontimer", "0")) * 30.0), int(cycle.definition.get("noautorange", "0")) != 0)})
				projectiles.append(projectile)
				shots_fired += 1
			elif int(shot.burst) > 0:
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
		if projectile.get("rocket", false):
			if step_rocket(projectile):
				survivors.append(projectile)
			continue
		if projectile.get("ballistic", false):
			if step_shell(projectile):
				survivors.append(projectile)
			continue
		if projectile.get("beam", false):
			if step_beam(projectile):
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
			apply_damage(target, Damage.amount(Damage.base_damage(projectile.damage, world.units[target].type), 1.0), next_raw)
			add_effect(end, str(projectile.get("explosion", "")))
			request_sound(str(projectile.get("soundhit", "")), end)
			continue
		projectile.previous = start
		projectile.position = end
		projectile.position_raw = next_raw
		projectile.distance += travel
		if world.collision.terrain_impact(world, projectile, int(projectile.get("collision_flags", 0))):
			add_effect(end, str(projectile.get("explosion", "")))
			request_sound(str(projectile.get("soundhit", "")), end)
			continue
		if projectile.has("deadline") or float(projectile.distance) < float(projectile.range):
			survivors.append(projectile)
	projectiles = survivors
	# Native updater snapshots its pool size: newly copied rounds move next tick.
	projectiles.append_array(burst_copies)
	process_deaths()

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

func step_rocket(projectile: Dictionary) -> bool:
	var state := {"position": projectile.position_raw, "velocity": projectile.velocity_raw,
		"speed": projectile.speed, "maximum": projectile.maximum, "acceleration": projectile.acceleration,
		"heading": projectile.heading, "pitch": projectile.pitch, "tick": tick, "deadline": projectile.deadline, "gravity": gravity}
	var next: Dictionary
	if projectile.get("guided", false):
		var target_point = null
		if world.units.has(int(projectile.target_id)):
			var target_unit: Dictionary = world.units[int(projectile.target_id)]
			target_point = raw_point(Vector3(target_unit.position.x, world.navigation.height_at(target_unit.position), target_unit.position.y))
		state.target = MissileTarget.select({"projectile": null, "unit": target_point, "unit_valid": target_point != null, "saved": projectile.saved_target}).point
		state.turn = projectile.turn
		next = GuidedMotion.advance(state)
		projectile.heading = next.heading
		projectile.pitch = next.pitch
	else:
		next = RocketMotion.advance(state)
	projectile.previous = projectile.position
	projectile.position_raw = next.position
	projectile.velocity_raw = next.velocity
	projectile.speed = next.speed
	projectile.position = render_point(next.position)
	if world.collision.projectile_cell(next.position) < 0:
		return false
	var target: int = world.collision.target_at(world, next.position, int(projectile.owner))
	if target != 0 or world.collision.terrain_impact(world, projectile, int(projectile.get("collision_flags", 0))):
		blast(projectile)
		return false
	return true

func step_beam(projectile: Dictionary) -> bool:
	var next := BeamMotion.advance({"head": projectile.position_raw, "tail": projectile.tail_raw, "velocity": projectile.velocity_raw,
		"released": projectile.released, "launch": projectile.launch, "duration": projectile.duration,
		"deadline": projectile.deadline, "tick": tick, "beam": true})
	if next.removed:
		return false
	projectile.previous = projectile.position
	projectile.position_raw = next.head
	projectile.position = render_point(next.head)
	projectile.tail_raw = next.tail
	projectile.tail = render_point(next.tail)
	projectile.released = next.released
	if world.collision.projectile_cell(next.head) < 0:
		return false
	# Impact dispatch 0x499eb0: a unit hit with area of effect below 17 deals direct damage, otherwise splash;
	# terrain impacts splash. noexplode (flag 0x400000) keeps the projectile alive after impact.
	var keep: bool = projectile.get("noexplode", false)
	var target: int = world.collision.target_at(world, next.head, int(projectile.owner))
	if target != 0:
		if int(projectile.get("area", 0)) < 17:
			apply_damage(target, Damage.amount(Damage.base_damage(projectile.damage, world.units[target].type), 1.0), next.head)
			add_effect(projectile.position, str(projectile.get("explosion", "")))
			request_sound(str(projectile.get("soundhit", "")), projectile.position)
		else:
			blast(projectile)
		return keep
	if world.collision.terrain_impact(world, projectile, int(projectile.get("collision_flags", 0))):
		blast(projectile)
		return keep
	return true

func destroy_unit(id: int) -> void:
	destroyed.append(id)
	world.remove_unit(id)
	stop(id)
	cycles.erase(id)
	command_cycles.erase(id)
	launch_offsets.erase(id)
	pending_deaths.erase(id)

## 0x489bb0/0x489ce0: a weapon hit (source_raw = projectile position) first applies the ARMORED damagemodifier, then
## the signed health word is reduced; at or below zero the unit is flagged dying (0x4000), ignores further damage until
## its update processes the death, and gets no scripts. Surviving weapon-hit victims queue HitByWeapon(cos, sin) and
## TakeDamage(percent) threads. Veterancy scaling awaits kill tracking.
func apply_damage(id: int, damage: int, source_raw = null, damage_type := 1) -> void:
	if not world.units.has(id) or pending_deaths.has(id):
		return
	var unit: Dictionary = world.units[id]
	# Unit +0xf5: the last damage type selects the death explosion (3 = self-destruct uses selfdestructas).
	unit.damage_type = damage_type
	var vm = world.scripts.get(id)
	var fields: Dictionary = world.catalog.definition(unit.type)
	if source_raw != null:
		var armored: bool = vm != null and int(vm.values.get(20, 0)) != 0
		damage = DamageNotify.armored_damage(damage, armored, int(float(fields.get("damagemodifier", "1")) * 65536.0))
	unit.health = Ground.signed16(int(unit.health) - (damage & 0xffff))
	hits += 1
	if int(unit.health) < 1:
		pending_deaths.append(id)
		return
	if source_raw == null or vm == null or not vm.fault.is_empty():
		return
	var record: Dictionary = world.collision.records.get(id, {})
	var unit_raw: Array = record.get("position_raw", [roundi(unit.position.x * 65536.0), 0, roundi(unit.position.y * 65536.0)])
	var heading := int(world.mobile_units[id].heading) if world.mobile_units.has(id) else 0
	var arguments := DamageNotify.hit_arguments(DamageNotify.angle_byte(source_raw, unit_raw, heading))
	var percent := DamageNotify.health_percent(int(unit.health), int(fields.get("maxdamage", "1")))
	notifications.append({"id": id, "tick": tick, "hit": arguments, "percent": percent})
	# Queued without running, as 0x4b0a70 is called with runNow=0; a unit with all eight threads busy drops them.
	for call: Array in [["HitByWeapon", arguments], ["TakeDamage", [percent]]]:
		if vm.functions.has(call[0]) and vm.active_threads() < vm.SLOT_COUNT:
			vm.invoke(call[0], call[1], false)

## Self-destruct background orders (handler 0x402010): id -> {counter, expired, wake, runs}.
var self_destructs: Dictionary = {}
## Local voice lines requested by the countdown: [id, "count5".."count0" or "canceldestruct"].
var voice_requests: Array = []

## FBI selfdestructcountdown, stored as 3 bits (& 7) with a default of 5.
static func self_destruct_countdown(fields: Dictionary) -> int:
	return (str(fields.selfdestructcountdown).to_int() & 7) if fields.has("selfdestructcountdown") else 5

## Ctrl+D over a selection: if any selected unit already has the order it is removed from those units, otherwise it
## is added to all. Removal after the final countdown run (expired) detonates immediately; earlier removal after the
## first run plays canceldestruct.
func toggle_self_destruct(ids: Array) -> bool:
	var active := ids.filter(func(id) -> bool: return self_destructs.has(int(id)))
	if active.is_empty():
		for id in ids:
			if world.units.has(int(id)) and not pending_deaths.has(int(id)):
				self_destructs[int(id)] = {"counter": self_destruct_countdown(world.catalog.definition(world.units[int(id)].type)), "expired": false, "wake": tick + 1, "runs": 0}
		return true
	for id in active:
		var order: Dictionary = self_destructs[int(id)]
		self_destructs.erase(int(id))
		if int(order.runs) == 0:
			continue
		if bool(order.expired):
			self_destruct_kill(int(id))
		elif not pending_deaths.has(int(id)):
			voice_requests.append([int(id), "canceldestruct"])
	return false

## Each run: an expired order (or countdown 0) kills; otherwise count n down with a 30-tick sleep, and at 0 mark it
## expired and sleep a game-RNG 0..14 ticks.
func step_self_destructs() -> void:
	for id: int in self_destructs.keys():
		if not world.units.has(id) or pending_deaths.has(id):
			self_destructs.erase(id)
			continue
		var order: Dictionary = self_destructs[id]
		if tick < int(order.wake):
			continue
		var countdown := self_destruct_countdown(world.catalog.definition(world.units[id].type))
		if bool(order.expired) or countdown == 0:
			self_destructs.erase(id)
			self_destruct_kill(id)
			continue
		var remaining := int(order.counter)
		voice_requests.append([id, "count%d" % remaining])
		if remaining == 0:
			order.expired = true
			order.wake = tick + world.game_random.bounded_random(15)
		else:
			order.counter = remaining - 1
			order.wake = tick + 30
		order.runs = int(order.runs) + 1

## 0x489bb0(unit, unit, 30000, 3, 0): target veterancy would reduce it to 24000..30000 (kills are not tracked yet).
func self_destruct_kill(id: int) -> void:
	apply_damage(id, 30000, null, 3)

## Suppress approach on an out-of-range event (0x403904..0x403957): a mobile unit moves to within R of the point and
## R shrinks by a game-RNG draw below range/3; at R <= 0 the lone order waits 30 + rand(30) ticks and restarts with R
## reset to the weapon range. The move-request semantics are provisional (a path to the point at distance R).
func step_ground_approach(source: int, order: Dictionary, origin: Vector2, destination: Vector2, within_range: bool, weapon_range: float) -> void:
	var mobile = world.mobile_units[source]
	if within_range:
		if order.chasing:
			mobile.stop()
			order.chasing = false
		return
	if tick < int(order.restart) or (order.chasing and not mobile.route.is_empty()):
		return
	if int(order.approach) <= 0:
		order.approach = int(weapon_range)
		order.restart = tick + 30 + world.game_random.bounded_random(30)
		order.chasing = false
		return
	var goal: Vector2 = destination + (origin - destination).normalized() * float(order.approach)
	order.chasing = mobile.move_to(mobile.navigation.nearest_open(goal))
	@warning_ignore("integer_division")
	order.approach = int(order.approach) - world.game_random.bounded_random(int(weapon_range) / 3)

func process_deaths() -> void:
	while not pending_deaths.is_empty():
		kill_unit(int(pending_deaths[0]))

## 0x4864b0 / 0x4866d0 for weapon deaths: severity, Killed corpse type, removal, then the explodeas death explosion.
func kill_unit(id: int) -> void:
	if not world.units.has(id):
		pending_deaths.erase(id)
		return
	var unit: Dictionary = world.units[id]
	var fields: Dictionary = world.catalog.definition(unit.type)
	var severity := death_severity(int(unit.health), int(fields.get("maxdamage", "1")), int(unit.get("previous_health_percent", 0)))
	var corpse := 0
	var debris: Array = []
	if world.scripts.has(id) and world.scripts[id].functions.has("Killed"):
		var vm = world.scripts[id]
		vm.explosions.clear()
		var invocation: int = vm.invoke("Killed", [severity, 0])
		if vm.completions.has(invocation):
			corpse = int(vm.completions[invocation].locals[1])
			vm.completions.erase(invocation)
		debris = vm.explosions.duplicate()
	var complete := float(unit.remaining) == 0.0
	if not complete:
		corpse = 0
	var position_raw: Array = world.collision.records[id].position_raw.duplicate() if world.collision.records.has(id) else [roundi(unit.position.x * 65536.0), 0, roundi(unit.position.y * 65536.0)]
	var rect: Rect2i = world.collision.records[id].rect if world.collision.records.has(id) else Rect2i(Vector2i(int(unit.position.x) >> 4, int(unit.position.y) >> 4), Vector2i.ONE)
	var team := int(unit.get("team", 0))
	var record := {"id": id, "type": unit.type, "severity": severity, "corpsetype": corpse, "corpse": str(fields.get("corpse", "")),
		"position": unit.position, "position_raw": position_raw, "team": team, "debris": debris, "tick": tick, "anchor": -1}
	deaths.append(record)
	destroy_unit(id)
	# 0x49b000: reason 3 (self-destruct) detonates selfdestructas (def+0x224) instead of explodeas (def+0x220).
	var blast_weapon := str(fields.get("selfdestructas" if int(unit.get("damage_type", 1)) == 3 else "explodeas", ""))
	var explosion: Dictionary = world.catalog.weapon(blast_weapon) if complete and severity > 0 else {}
	if not explosion.is_empty():
		var definition: Dictionary = explosion.definition
		blast({"source": id, "owner": team, "position": render_point(position_raw), "position_raw": position_raw,
			"area": int(definition.get("areaofeffect", "0")), "edge": float(definition.get("edgeeffectiveness", "0")),
			"explosion": str(definition.get("explosiongaf", "")) + "/" + str(definition.get("explosionart", "")),
			"soundhit": str(definition.get("soundhit", "")), "damage": definition.get("damage", {}), "firestarter": int(definition.get("firestarter", "0")),
			"collision_flags": world.collision.collision_flags(definition)})
	# 0x486360 after the explosion: the corpse (or its featuredead heap) anchors at the unit's collision rectangle cell.
	if corpse > 0 and "features" in world and world.features != null:
		record.anchor = world.features.place_corpse(str(fields.get("corpse", "")), corpse, rect.position.x, rect.position.y, position_raw, team)
		if int(record.anchor) >= 0:
			world.refresh_feature_blocking()

## Killed severity: ((-health * 100) as unsigned / maxdamage + previous health percent) / 2, clamped to 1..100.
static func death_severity(health: int, maxdamage: int, previous_percent: int) -> int:
	@warning_ignore("integer_division")
	var overkill := ((-health * 100) & 0xffffffff) / maxi(1, maxdamage)
	@warning_ignore("integer_division")
	return clampi(int((overkill + (previous_percent & 0xff)) / 2), 1, 100)

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
	if target != 0 or world.collision.terrain_impact(world, projectile, int(projectile.get("collision_flags", 0))):
		blast(projectile)
		return false
	return true

func add_effect(position: Vector3, key: String) -> void:
	var frames: Array = effect_assets.frames(key)
	var duration := frames.size() if not frames.is_empty() else 8
	effects.append({"position": position, "life": duration, "duration": duration, "explosion": key})

func request_sound(name: String, position: Vector3) -> void:
	if not name.is_empty():
		sound_requested.emit(name, position)

func blast(projectile: Dictionary) -> void:
	request_sound(str(projectile.get("soundhit", "")), projectile.position)
	add_effect(projectile.position, str(projectile.get("explosion", "")))
	@warning_ignore("integer_division")
	var radius: int = int(projectile.area) / 2
	for id: int in world.collision.records.keys():
		if id == int(projectile.source) or not world.collision.records.has(id) or not world.units.has(id):
			continue
		var record: Dictionary = world.collision.records[id]
		var multiplier := Splash.multiplier(projectile.position_raw, record.position_raw, record.bounds.lower, record.bounds.upper, radius, float(projectile.edge))
		if multiplier <= 0:
			continue
		apply_damage(id, Damage.amount(Damage.base_damage(projectile.damage, world.units[id].type), multiplier), projectile.position_raw)
	# 0x49a120 feature pass: features within half the area of effect take the weapon's default damage (0x4244b0).
	if "features" in world and world.features != null:
		var weapon := {"default": int(str(projectile.damage.get("default", "0")).to_int()), "area": int(projectile.get("area", 0)),
			"firestarter": int(projectile.get("firestarter", 0)), "flags": int(projectile.get("collision_flags", 0))}
		var result := FeatureDamage.splash(world.features, weapon, projectile.position_raw, GAME_FLAGS)
		for call: Array in result.replaced:
			world.features.replace(int(call[1]) * int(world.features.width) + int(call[0]), false)
		feature_ignitions.append_array(result.ignited)
		if not result.replaced.is_empty():
			feature_destructions += result.replaced.size()
			world.refresh_feature_blocking()
