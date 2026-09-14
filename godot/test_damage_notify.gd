extends SceneTree
## Damage notifications: hit angle byte, HitByWeapon arguments, TakeDamage percent, ARMORED damagemodifier and the
## live world gating (queued threads, no scripts on a killing hit).
const Catalog = preload("res://unit_catalog.gd")
const Navigation = preload("res://terrain_navigation.gd")
const World = preload("res://construction_world.gd")
const Combat = preload("res://combat_world.gd")
const DamageNotify = preload("res://damage_notify.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func queued(vm: RefCounted, name: String) -> int:
	var count := 0
	for thread in vm.slots:
		if thread != null and thread.name == name:
			count += 1
	return count

func _initialize() -> void:
	check(DamageNotify.hit_arguments(0) == [400, 0], "A hit from straight ahead gives HitByWeapon(400, 0)")
	check(DamageNotify.hit_arguments(64) == [0, 400], "A quarter turn gives HitByWeapon(0, 400)")
	check(DamageNotify.hit_arguments(128) == [-400, 0] and DamageNotify.hit_arguments(192) == [0, -400], "Opposite directions negate")
	check(DamageNotify.hit_arguments(32) == [283, 283], "Diagonals round through the 512 sine table")
	var unit := [100 * 65536, 0, 100 * 65536]
	check(DamageNotify.angle_byte([100 * 65536, 0, 164 * 65536], unit, 0) == 0, "A projectile on +z has angle byte 0")
	check(DamageNotify.angle_byte([164 * 65536, 0, 100 * 65536], unit, 0) == 64, "A projectile on +x has angle byte 64")
	check(DamageNotify.angle_byte([164 * 65536, 0, 100 * 65536], unit, 16384) == 0, "The unit heading is subtracted before taking the high byte")
	check(DamageNotify.angle_byte([100 * 65536, 0, 36 * 65536], unit, 0) == 128, "A projectile on -z has angle byte 128")
	check(DamageNotify.health_percent(50, 200) == 25 and DamageNotify.health_percent(199, 200) == 99 and DamageNotify.health_percent(300, 200) == 100, "TakeDamage percent truncates and clamps")
	check(DamageNotify.armored_damage(90, true, 0x8000) == 45 and DamageNotify.armored_damage(90, false, 0x8000) == 90, "ARMORED scales damage by the 16.16 damagemodifier")
	check(DamageNotify.armored_damage(30000, true, 0x8000) == 30000 and DamageNotify.armored_damage(29999, true, 0x8000) == 14999, "Damage of 30000 or more bypasses the modifier")
	var catalog = Catalog.new(ProjectSettings.globalize_path("res://../local/unit-assets/"))
	var heights := PackedByteArray()
	heights.resize(64 * 64)
	heights.fill(0)
	var world = World.new(catalog, Navigation.new(64, 64, heights), Vector2(96, 96))
	var combat = Combat.new(world)
	var tank: int = world.add_unit("armflash", Vector2(512, 512), 0.0, 1)
	world.collision.sync(world)
	var raw: Array = world.collision.records[tank].position_raw
	var vm = world.scripts[tank]
	var health: int = world.units[tank].health
	combat.apply_damage(tank, 100, [int(raw[0]) + 40 * 65536, int(raw[1]), int(raw[2])])
	check(int(world.units[tank].health) == health - 100, "The weapon hit reduces health")
	check(queued(vm, "HitByWeapon") == 1 and combat.notifications.size() == 1 and combat.notifications[0].hit == DamageNotify.hit_arguments(64), "A surviving victim queues HitByWeapon with the hit direction")
	check(int(combat.notifications[0].percent) == DamageNotify.health_percent(health - 100, 625), "TakeDamage receives the remaining health percent")
	check(vm.fault.is_empty(), "Queued notifications do not fault the script")
	combat.apply_damage(tank, 100)
	check(combat.notifications.size() == 1, "Non-weapon damage (no projectile position) issues no scripts")
	combat.apply_damage(tank, 5000, raw)
	check(combat.notifications.size() == 1 and combat.pending_deaths.has(tank), "A killing hit flags the unit dying without scripts")
	# ARMORED solar collectors (closed by Deactivate) take a third of the damage.
	var solar: int = world.add_unit("armsolar", Vector2(256, 512), 0.0, 1)
	world.set_active(solar, false)
	for tick in range(120):
		world.step()
	world.collision.sync(world)
	var solar_vm = world.scripts[solar]
	var solar_health: int = world.units[solar].health
	check(int(solar_vm.values.get(20, 0)) != 0, "The closed solar script sets ARMORED")
	combat.apply_damage(solar, 90, world.collision.records[solar].position_raw)
	check(int(world.units[solar].health) == solar_health - DamageNotify.armored_damage(90, true, int(0.33333 * 65536.0)), "ARMORED damage uses the unit's damagemodifier")
	# Veterancy: attackers add 6% per level (kills / 5, max 5); targets remove 4% per level after armor.
	check(DamageNotify.attacker_veterancy(100, 10) == 112 and DamageNotify.attacker_veterancy(100, 99) == 130 and DamageNotify.attacker_veterancy(100, 4) == 100, "Attacker veterancy scales by (6k + 100) / 100")
	check(DamageNotify.target_veterancy(100, 5) == 96 and DamageNotify.target_veterancy(30000, 25) == 24000 and DamageNotify.target_veterancy(77, 0) == 77, "Target veterancy scales by (25 - k) * 4 / 100")
	var hunter: int = world.add_unit("armflash", Vector2(700, 700), 0.0, 0)
	var prey: int = world.add_unit("corraid", Vector2(760, 700), 0.0, 1)
	var ally: int = world.add_unit("armflash", Vector2(700, 900), 0.0, 0)
	var unfinished: int = world.add_unit("corraid", Vector2(300, 900), 0.5, 1)
	world.collision.sync(world)
	world.units[hunter].experience = 10
	var prey_health: int = world.units[prey].health
	combat.apply_damage(prey, 50, world.collision.records[prey].position_raw, 1, hunter)
	check(int(world.units[prey].health) == prey_health - 56, "A veteran attacker's hit deals boosted damage")
	combat.apply_damage(prey, 5000, world.collision.records[prey].position_raw, 1, hunter)
	combat.process_deaths()
	check(not world.units.has(prey) and int(world.units[hunter].experience) == 11 and int(combat.deaths[-1].get("killer", 0)) == hunter, "Killing an enemy unit credits the attacker's kill word")
	combat.apply_damage(ally, 5000, world.collision.records[ally].position_raw, 1, hunter)
	combat.process_deaths()
	check(int(world.units[hunter].experience) == 11, "Killing a unit of the same owner gives no credit")
	combat.apply_damage(unfinished, 5000, world.collision.records[unfinished].position_raw, 1, hunter)
	combat.process_deaths()
	check(not world.units.has(unfinished) and int(world.units[hunter].experience) == 11, "Unfinished victims give no credit")
	print("DAMAGE_NOTIFY %d / %d checks pass" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
