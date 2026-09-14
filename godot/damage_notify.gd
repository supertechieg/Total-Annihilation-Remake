extends RefCounted
## Damage-side script notifications and the armored modifier. See analysis/DAMAGE_NOTIFICATIONS.md.
## 0x499cd0 builds the hit angle, 0x489bb0 applies ARMORED/damagemodifier, 0x489ce0 subtracts health and starts
## HitByWeapon(cos, sin) then TakeDamage(percent) as queued threads for weapon hits (damage type 1).
const Ground = preload("res://ground_motion.gd")
static var sine: Array[int] = []

static func table() -> Array[int]:
	if sine.is_empty():
		for index in range(512):
			sine.append(roundi(sin(index * TAU / 512.0) * 8192.0))
	return sine

## 0x499d80: high byte of (atan2(proj.x - unit.x, proj.z - unit.z) in TA angle units - heading).
static func angle_byte(projectile_raw: Array, unit_raw: Array, heading: int) -> int:
	var dx := Ground.signed32(int(projectile_raw[0]) - int(unit_raw[0]))
	var dz := Ground.signed32(int(projectile_raw[2]) - int(unit_raw[2]))
	var angle := roundi(atan2(float(dx), float(dz)) * 10430.37835047)
	return ((angle - (heading & 0xffff)) & 0xffff) >> 8

## 0x489f04..0x489f43: HitByWeapon arguments 400*cos and 400*sin of the angle byte << 8, rounded through the 512 sine table.
static func hit_arguments(byte: int) -> Array:
	var values := table()
	var cosine := int(values[(2 * (byte & 0xff) + 128) % 512])
	var sine_value := int(values[(2 * (byte & 0xff)) % 512])
	return [(cosine * 400 + 4096) >> 13, (sine_value * 400 + 4096) >> 13]

## TakeDamage argument: (u32)(health * 100) / maxdamage clamped to 0..100.
static func health_percent(health: int, maxdamage: int) -> int:
	@warning_ignore("integer_division")
	return clampi(((health * 100) & 0xffffffff) / maxi(1, maxdamage & 0xffffffff), 0, 100)

static func trunc_div(value: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	var quotient := absi(value) / divisor
	return -quotient if value < 0 else quotient

## Veterancy level from the unit +0xb8 kill word: min(kills / 5, 5).
static func veterancy_level(experience: int) -> int:
	@warning_ignore("integer_division")
	return mini((experience & 0xffff) / 5, 5)

## 0x499dae: an attacking unit adds 6% damage per veterancy level (32-bit product, truncating division).
static func attacker_veterancy(damage: int, experience: int) -> int:
	return trunc_div(Ground.signed32((6 * veterancy_level(experience) + 100) * damage), 100)

## 0x489bf3: the damaged unit removes 4% per veterancy level, applied after the armored modifier.
static func target_veterancy(damage: int, experience: int) -> int:
	return trunc_div(Ground.signed32(Ground.signed32((25 - veterancy_level(experience)) * damage) * 4), 100)

## 0x489bc3: a unit whose script set ARMORED takes damage * damagemodifier (16.16) >> 16 for damage below 30000.
static func armored_damage(damage: int, armored: bool, modifier: int) -> int:
	if not armored or damage >= 30000:
		return damage
	return Ground.signed32((damage * modifier) >> 16)
