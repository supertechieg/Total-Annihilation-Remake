extends RefCounted
## Provisional opponent policy using the normal production and combat APIs.
var world: RefCounted
var combat: RefCounted
var team: int
var next_decision := 0
var queued := 0
var attacks := 0
var structures_started := 0

func _init(source: RefCounted, battle: RefCounted, owner: int) -> void:
	world = source
	combat = battle
	team = owner

func step() -> void:
	if world.ticks < next_decision:
		return
	next_decision = world.ticks + 30
	build_base()
	for id: int in world.factories:
		if int(world.units[id].get("team", 0)) != team or float(world.units[id].remaining) > 0:
			continue
		var factory: Dictionary = world.factories[id]
		if not factory.queue.is_empty() or int(factory.product) != 0:
			continue
		var type := "armpw" if world.units[id].type == "armlab" else "armflash"
		if world.queue_unit(id, type):
			queued += 1
	for id: int in world.units:
		var unit: Dictionary = world.units[id]
		if int(unit.get("team", 0)) != team or float(unit.remaining) > 0 or unit.type not in combat.SUPPORTED_UNITS:
			continue
		if combat.orders.has(id) and world.units.has(int(combat.orders[id].target)):
			continue
		# Let factory exit movement finish before issuing the first attack.
		if world.mobile_units.has(id) and not world.mobile_units[id].route.is_empty():
			continue
		var target := 0
		var nearest := INF
		for candidate: int in world.units:
			var enemy: Dictionary = world.units[candidate]
			if int(enemy.get("team", 0)) == team:
				continue
			var distance: float = unit.position.distance_squared_to(enemy.position)
			if distance < nearest:
				nearest = distance
				target = candidate
		if target != 0 and combat.attack(id, target, true):
			attacks += 1

func build_base() -> void:
	var has_solar := false
	var has_factory := false
	for unit: Dictionary in world.units.values():
		if int(unit.get("team", 0)) == team:
			has_solar = has_solar or unit.type == "armsolar"
			has_factory = has_factory or unit.type in ["armvp", "armlab"]
	var type := "armsolar" if not has_solar else "armvp"
	if has_solar and has_factory:
		return
	for id: int in world.units.keys():
		var unit: Dictionary = world.units[id]
		if int(unit.get("team", 0)) != team or not world.can_build(id):
			continue
		if world.builder_jobs.has(id) or (id == world.builder_id and world.task_id != 0):
			continue
		if type not in world.catalog.build_options(unit.type):
			continue
		for radius in [64, 96, 128]:
			for offset in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius), Vector2(radius, radius), Vector2(-radius, -radius)]:
				var point: Vector2 = unit.position + offset
				if world.placement_error(type, point, id).is_empty() and world.begin_build(type, point, id) != 0:
					structures_started += 1
					return
