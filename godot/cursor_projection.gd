extends RefCounted
## Original cursor projection 0x484b50: a view point (sx, sy) in scrolled map pixels becomes a 16.16 world point on the
## terrain. It steps down from 128 px below the point's 16 px row until the projected surface z - (h >> 1) is at or above sy,
## then interpolates z between that row and the next. Heights come from 0x485070 raised to the sea level.
const FeatureDamage = preload("res://feature_damage.gd")

static func signed32(value: int) -> int:
	value &= 0xffffffff
	return value - 0x100000000 if value >= 0x80000000 else value

static func surface(heights: PackedByteArray, cells_w: int, cells_h: int, sea: int, x_raw: int, z_raw: int) -> int:
	return maxi(FeatureDamage.height(heights, cells_w, cells_h, x_raw, z_raw), sea)

static func projected(z_raw: int, height: int) -> int:
	return FeatureDamage.signed16(z_raw >> 16) - (height >> 1)

## Returns [x, y, z] in 16.16 exactly as the native output record.
static func screen_to_world(heights: PackedByteArray, cells_w: int, cells_h: int, map_w: int, map_h: int, sea: int, sx: int, sy: int) -> Array:
	sx = mini(maxi(sx, 0), map_w - 1) if sx < map_w else map_w - 1
	sy = mini(maxi(sy, 0), map_h - 1) if sy < map_h else map_h - 1
	var x := signed32(sx << 16)
	var z := signed32(((sy & ~0xf) + 0x80) << 16)
	var step := 0x80
	var h0 := 0
	var s0 := 0
	while true:
		h0 = surface(heights, cells_w, cells_h, sea, x, z)
		s0 = projected(z, h0)
		if s0 <= sy:
			break
		step -= 0x10
		z = signed32(z - 0x100000)
		if step < 0:
			# Unreachable with byte heights; the native routine returns the last sample (z already stepped past it).
			return [x, h0 << 16, signed32(z + 0x100000)]
	var next_z := signed32(z + 0x100000)
	var s1 := projected(next_z, surface(heights, cells_w, cells_h, sea, x, next_z))
	if ((s0 < s1 and sy >= s0) or sy <= s1) and s1 != s0:
		var numerator := signed32((sy - s0) << 20)
		var denominator := s1 - s0
		var quotient := absi(numerator) / absi(denominator)
		if (numerator < 0) != (denominator < 0):
			quotient = -quotient
		var world_z := signed32(z + quotient)
		return [x, surface(heights, cells_w, cells_h, sea, x, world_z) << 16, world_z]
	return [x, h0 << 16, z]
