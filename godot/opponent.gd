extends RefCounted
## Provisional opponent policy using the normal production and combat APIs.
## Faction tables choose each side's original level-one builders, factories, combat units and economy structures.
const FACTIONS := {
	"arm": {"builders": ["armcv", "armck"], "commander": "armcom", "vehicle_plant": "armvp", "kbot_lab": "armlab",
		"vehicle_combat": "armflash", "kbot_combat": "armpw", "vehicle_builder": "armcv", "kbot_builder": "armck",
		"solar": "armsolar", "extractor": "armmex"},
	"core": {"builders": ["corcv", "corck"], "commander": "corcom", "vehicle_plant": "corvp", "kbot_lab": "corlab",
		"vehicle_combat": "corraid", "kbot_combat": "corak", "vehicle_builder": "corcv", "kbot_builder": "corck",
		"solar": "corsolar", "extractor": "cormex"},
}
var world: RefCounted
var combat: RefCounted
var team: int
var faction := "arm"
var roster: Dictionary
var next_decision := 0
var queued := 0
var attacks := 0
var structures_started := 0
var structures_resumed := 0
var metal_sites: Array[Vector2] = []

func _init(source: RefCounted, battle: RefCounted, owner: int, side := "arm") -> void:
	world = source
	combat = battle
	team = owner
	faction = side if FACTIONS.has(side) else "arm"
	roster = FACTIONS[faction]
	for index in range(world.terrain_metal.size()):
		if world.terrain_metal[index] > 0:
			metal_sites.append(Vector2((index % world.navigation.width) * 16, (index / world.navigation.width) * 16))

func step() -> void:
	if world.ticks < next_decision:
		return
	next_decision = world.ticks + 30
	build_base()
	var builder_available := false
	for unit: Dictionary in world.units.values():
		if int(unit.get("team", 0)) == team and (unit.type in roster.builders or unit.type == roster.commander):
			builder_available = true
	for factory_id: int in world.factories:
		if int(world.units[factory_id].get("team", 0)) == team:
			for pending in world.factories[factory_id].queue:
				builder_available = builder_available or pending in roster.builders
	for id: int in world.factories:
		if int(world.units[id].get("team", 0)) != team or float(world.units[id].remaining) > 0:
			continue
		var factory: Dictionary = world.factories[id]
		if not factory.queue.is_empty() or int(factory.product) != 0:
			continue
		var kbot: bool = world.units[id].type == roster.kbot_lab
		var type: String = roster.kbot_combat if kbot else roster.vehicle_combat
		if not builder_available:
			type = roster.kbot_builder if kbot else roster.vehicle_builder
		if world.queue_unit(id, type):
			queued += 1
			if type in roster.builders:
				builder_available = true
	for id: int in world.units:
		var unit: Dictionary = world.units[id]
		if int(unit.get("team", 0)) != team or float(unit.remaining) > 0 or unit.type not in combat.SUPPORTED_UNITS:
			continue
		# The Commander stays home to build and defend; only produced units are sent to attack.
		if unit.type == roster.commander:
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
	var assigned: Array = []
	for job: Dictionary in world.builder_jobs.values():
		assigned.append(int(job.target))
	if world.task_id != 0:
		assigned.append(int(world.task_id))
	for builder: int in world.units.keys():
		if int(world.units[builder].get("team", 0)) != team or not world.can_build(builder):
			continue
		if world.builder_jobs.has(builder) or (builder == world.builder_id and world.task_id != 0):
			continue
		for target: int in world.units.keys():
			var unfinished: Dictionary = world.units[target]
			if target in assigned or int(unfinished.get("team", 0)) != team or float(unfinished.remaining) <= 0:
				continue
			if int(world.catalog.definition(unfinished.type).get("bmcode", "1")) != 0:
				continue
			if unfinished.type not in world.catalog.build_options(world.units[builder].type):
				continue
			if world.resume_build(target, builder):
				structures_resumed += 1
				return
	var has_solar := false
	var has_factory := false
	var pending_solar := false
	var energy_debt := 0.0
	for unit: Dictionary in world.units.values():
		if int(unit.get("team", 0)) == team:
			has_solar = has_solar or unit.type == roster.solar
			has_factory = has_factory or unit.type in [roster.vehicle_plant, roster.kbot_lab]
			pending_solar = pending_solar or (unit.type == roster.solar and float(unit.remaining) > 0)
			energy_debt += float(unit.energy_ledger.debt)
	var type: String = roster.solar if not has_solar else roster.vehicle_plant
	if has_solar and has_factory:
		if energy_debt > 0 and not pending_solar:
			type = roster.solar
		else:
			build_extractor()
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

func build_extractor() -> void:
	# Expand again when normal construction accumulates unpaid metal debt.
	var has_extractor := false
	var metal_debt := 0.0
	for unit: Dictionary in world.units.values():
		if int(unit.get("team", 0)) != team:
			continue
		metal_debt += float(unit.metal_ledger.debt)
		if unit.type == roster.extractor:
			has_extractor = true
			if float(unit.remaining) > 0:
				return
	if has_extractor and metal_debt <= 0:
		return
	for id: int in world.units.keys():
		var unit: Dictionary = world.units[id]
		if int(unit.get("team", 0)) != team or not world.can_build(id) or world.builder_jobs.has(id):
			continue
		if roster.extractor not in world.catalog.build_options(unit.type) or not world.mobile_units.has(id):
			continue
		if not world.mobile_units[id].route.is_empty():
			continue
		var sites := metal_sites.duplicate()
		sites.sort_custom(func(a: Vector2, b: Vector2) -> bool: return unit.position.distance_squared_to(a) < unit.position.distance_squared_to(b))
		for point: Vector2 in sites:
			var error: String = world.placement_error(roster.extractor, point, id)
			if error.is_empty():
				if world.begin_build(roster.extractor, point, id) != 0:
					structures_started += 1
					return
			elif error == "Move builder closer to build site":
				for offset: Vector2 in [Vector2(64, 0), Vector2(-64, 0), Vector2(0, 64), Vector2(0, -64)]:
					if world.move_unit(id, point + offset):
						return
