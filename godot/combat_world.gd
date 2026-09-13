extends RefCounted
## Initial EMG combat host. See analysis/COMBAT.md for provisional simulation rules.
const Cycle = preload("res://weapon_cycle.gd")
const Origin = preload("res://piece_origin.gd")
const Damage = preload("res://weapon_damage.gd")
var world: RefCounted
var orders: Dictionary = {}
var cycles: Dictionary = {}
var projectiles: Array = []
var effects: Array = []
var destroyed: Array[int] = []
var shots_fired := 0
var hits := 0
var status := ""

func _init(source: RefCounted) -> void:
	world = source

func stop(id: int) -> void:
	orders.erase(id)
	if cycles.has(id):
		cycles[id].stop()

func attack(source: int, target: int) -> bool:
	if not world.units.has(source) or not world.units.has(target) or source == target:
		return false
	if world.units[source].type != "armflash" or float(world.units[source].remaining) > 0:
		status = "Combat currently supports completed Flash tanks"
		return false
	if world.units[source].get("team", 0) == world.units[target].get("team", 0):
		status = "Select an enemy target"
		return false
	if not cycles.has(source):
		cycles[source] = Cycle.new(world.scripts[source], world.catalog.weapon("EMG"))
	world.mobile_units[source].stop()
	orders[source] = {"target": target, "heading": -999999, "pitch": -999999}
	status = "Attacking target"
	return true

func center(id: int) -> Vector3:
	var unit: Dictionary = world.units[id]
	return Vector3(unit.position.x, world.navigation.height_at(unit.position) + 12.0, unit.position.y)

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
		var heading := roundi(atan2(aim_origin.x - destination.x, aim_origin.z - destination.y) * 65536.0 / TAU) - int(world.mobile_units[source].heading)
		var within_range := origin.distance_to(destination) <= float(cycle.definition.get("range", "0"))
		if cycle.aim_id < 0 and (not cycle.requested or heading != int(order.heading)):
			cycle.aim(heading, 0)
			order.heading = heading
		cycle.step(within_range and world.mobile_units[source].speed == 0)
		if not cycle.fault.is_empty():
			status = cycle.fault
			stop(source)
			continue
		for shot: Dictionary in cycle.shots:
			var start := muzzle(source, shot.piece_name)
			var direction := (center(target) - start).normalized()
			var velocity_raw := [int(direction.x * int(shot.velocity_raw_per_tick)), int(direction.y * int(shot.velocity_raw_per_tick)), int(direction.z * int(shot.velocity_raw_per_tick))]
			projectiles.append({"source": source, "owner": int(world.units[source].get("team", 0)), "position": start, "previous": start,
				"position_raw": raw_point(start), "velocity_raw": velocity_raw,
				"distance": 0.0, "range": float(cycle.definition.range), "damage": cycle.definition.get("damage", {"default": "8"})})
			shots_fired += 1
	var survivors: Array = []
	for projectile: Dictionary in projectiles:
		var start: Vector3 = projectile.position
		var velocity := render_point(projectile.velocity_raw)
		var travel := minf(velocity.length(), maxf(0, float(projectile.range) - float(projectile.distance)))
		if travel <= 0:
			continue
		var fraction := travel / velocity.length()
		var next_raw: Array = projectile.position_raw.duplicate()
		for axis in range(3):
			next_raw[axis] = int(next_raw[axis]) + int(int(projectile.velocity_raw[axis]) * fraction)
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
			continue
		projectile.previous = start
		projectile.position = end
		projectile.position_raw = next_raw
		projectile.distance += travel
		if float(projectile.distance) < float(projectile.range) and end.y >= world.navigation.height_at(Vector2(end.x, end.z)):
			survivors.append(projectile)
	projectiles = survivors
