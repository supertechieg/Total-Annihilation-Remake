extends RefCounted
## Provisional opponent policy using the normal production and combat APIs.
var world: RefCounted
var combat: RefCounted
var team: int
var next_decision := 0
var queued := 0
var attacks := 0

func _init(source: RefCounted, battle: RefCounted, owner: int) -> void:
	world = source
	combat = battle
	team = owner

func step() -> void:
	if world.ticks < next_decision:
		return
	next_decision = world.ticks + 30
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
