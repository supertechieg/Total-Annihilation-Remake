extends RefCounted
## R6 visibility queries, verified against the original TotalA.exe by tools/native_visibility_query.py (O5).
##
## Inputs are plain data so tests can drive these without VisibilityWorld:
##   rec   = {"index": int, "w2": int, "h2": int, "los": PackedByteArray}   (player record +0x146/+0x80/+0x84/+0x7c)
##   world = {"flags": int (game+0x14281), "mapped": PackedByteArray (game+0x14273, u16 LE per LOS cell),
##            "local_player": int (byte game+0x2a43), "sea_level": int (byte game+0x1427f)}
##   unit  = {"owner": int player index (unit+0x96 record), "state10e": int, "vis_flags": int (unit+0x110),
##            "pos16": [x, y, z] 16.16, "bounds": [d15e, d16e, d166, d176, d17a, d17e]}
## Owner identity is compared by player index; the original compares record pointers (one record per index).

static func s16(v: int) -> int:
	return ((v & 0xFFFF) ^ 0x8000) - 0x8000

static func s32(v: int) -> int:
	return ((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000

## LOS cell index for a 16.16 point, or -1 when outside rec w2/h2 (unsigned 32-bit compare).
static func cell_index(rec: Dictionary, x16: int, y16: int, z16: int) -> int:
	var col := s16(x16 >> 16) >> 5
	var row := (s16(z16 >> 16) - (s16(y16 >> 16) >> 1)) >> 5
	return _index(rec, col, row)

static func _index(rec: Dictionary, col: int, row: int) -> int:
	var w2 := int(rec.w2)
	if (col & 0xFFFFFFFF) >= (w2 & 0xFFFFFFFF) or (row & 0xFFFFFFFF) >= (int(rec.h2) & 0xFFFFFFFF):
		return -1
	return row * w2 + col

## Mapped word test at a cell: always the LOCAL player's bit (byte shift masked to 5 bits like x86 shl).
static func _mapped_bit(world: Dictionary, index: int) -> bool:
	var mapped: PackedByteArray = world.mapped
	var word := mapped[index * 2] | (mapped[index * 2 + 1] << 8)
	return (word & (1 << (int(world.local_player) & 31))) != 0

static func _cell_test(rec: Dictionary, world: Dictionary, index: int) -> bool:
	if index < 0:
		return false
	if (int(world.flags) & 2) != 0:
		var los: PackedByteArray = rec.los
		return los[index] != 0
	return _mapped_bit(world, index)

## 0x408090 stdcall(rec, P16*): mapped-only probe; ignores the LOS mode flag.
static func mapped_probe(rec: Dictionary, world: Dictionary, p: Array) -> bool:
	var index := cell_index(rec, int(p[0]), int(p[1]), int(p[2]))
	return index >= 0 and _mapped_bit(world, index)

## Probe used by 0x465ac0 (and 0x467440 phase 5): LOS byte grid when flags&2, else 0x408090.
static func probe(rec: Dictionary, world: Dictionary, p: Array) -> bool:
	return _cell_test(rec, world, cell_index(rec, int(p[0]), int(p[1]), int(p[2])))

## Definition bounds [d15e, d16e, d166, d176, d17a, d17e] from UnitBounds.from_unit (loader 0x42d079-0x42d107).
static func definition_bounds(unit_bounds: Dictionary) -> Array:
	var lower: Array = unit_bounds.lower
	var upper: Array = unit_bounds.upper
	return [s32(int(lower[0])), s32(int(upper[1])), s32(int(lower[2])),
		s32(int(upper[0]) - int(lower[0])), s32(int(upper[1]) - int(lower[1])), s32(int(upper[2]) - int(lower[2]))]

## 0x465ac0 stdcall(rec, unit).
static func visible(rec: Dictionary, world: Dictionary, unit: Dictionary) -> bool:
	if int(unit.owner) == int(rec.index):
		return true
	if (int(unit.state10e) & 4) != 0:
		return false
	var pos: Array = unit.pos16
	var b: Array = unit.bounds
	var x := s32(int(pos[0]) + int(b[0]))
	var y := s32(int(pos[1]) + int(b[1]))
	var z := s32(int(pos[2]) + int(b[2]))
	if (int(unit.vis_flags) & 0x200) == 0 and y < ((int(world.sea_level) & 0xFF) << 16):
		return false
	if probe(rec, world, [x, y, z]):
		return true
	x = s32(x + int(b[3]))
	if probe(rec, world, [x, y, z]):
		return true
	y = s32(y - int(b[4]))
	z = s32(z + int(b[5]))
	if probe(rec, world, [x, y, z]):
		return true
	x = s32(x - int(b[3]))
	return probe(rec, world, [x, y, z])

## 0x4658e0 stdcall(rec, col, row, fpx, fpz, h): feature footprint corners, all 16-bit pixel math.
static func feature_visible(rec: Dictionary, world: Dictionary, col: int, row: int, fpx: int, fpz: int, h: int) -> bool:
	var half := s16(h) >> 1
	var ax := s16(col << 4)
	var az := s16(row << 4) - half          # 32-bit subtraction after sign extension
	if _cell_test(rec, world, _index(rec, ax >> 5, az >> 5)):
		return true
	var bx := s16((col << 4) + (fpx << 4))
	var bz := s16((row << 4) + (fpz << 4)) - half
	return _cell_test(rec, world, _index(rec, bx >> 5, bz >> 5))
