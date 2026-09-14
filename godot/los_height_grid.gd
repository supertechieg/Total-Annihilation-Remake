extends RefCounted
## LosHeightGrid (preload by path, as the other ported modules are): true-LOS terrain height grid built at map load by the original 0x482c20 (core 0x482f1b..0x483205).
## Each half-resolution LOS cell stores two bytes: the maximum then the minimum projected terrain height.

## heights: one byte per 16-px map cell (TNT attribute byte 0, game cell +4), row-major, map_w x map_h.
static func build(heights: PackedByteArray, map_w: int, map_h: int, sea_level: int) -> Dictionary:
	# cdq/sub/sar 1: signed division truncating toward zero.
	var w2 := int(map_w / 2)
	var h2 := int(map_h / 2)
	var pad := (w2 * h2 + 7) & ~7
	var grid := PackedByteArray()
	grid.resize(pad * 2)
	for e in range(pad):
		grid[e * 2] = 0
		grid[e * 2 + 1] = 0xff
	for c in range(map_w):
		var ax := (c - 1) >> 1
		var bx := c >> 1
		# Carried cell pointers A (column (c-1)>>1) and B (column c>>1 when different); -1 is null.
		var a := -1
		var b := -1
		for r in range(map_h):
			var h := heights[r * map_w + c]
			var py := 16 * r - (h >> 1)
			var lr := py >> 5
			if lr >= 0:
				# Signed idiv; both operands are non-negative here, and s <= h.
				var s := int((((lr << 5) + 31) * h) / (py + 31))
				_apply(grid, a, s)
				_apply(grid, b, s)
				a = -1
				if ax >= 0 and ax < w2 and lr < h2:
					a = (lr * w2 + ax) * 2
					_apply(grid, a, s)
				b = -1
				if ax != bx and bx < w2 and lr < h2:
					b = (lr * w2 + bx) * 2
					_apply(grid, b, s)
			# Applied for every row; rows with lr < 0 only reach the cells carried from earlier rows.
			_apply(grid, a, h)
			_apply(grid, b, h)
	# 1/3-2/3 blend over every padded entry, clamped below by sea level.
	var sea := sea_level & 0xff
	for e in range(pad):
		var b0 := grid[e * 2]
		var b1 := grid[e * 2 + 1]
		grid[e * 2] = maxi(int((b1 + 2 * b0) / 3), sea)
		grid[e * 2 + 1] = maxi(int((b0 + 2 * b1) / 3), sea)
	return {"w2": w2, "h2": h2, "pad": pad, "grid": grid}


static func _apply(grid: PackedByteArray, at: int, value: int) -> void:
	if at < 0:
		return
	if value > grid[at]:
		grid[at] = value
	if value < grid[at + 1]:
		grid[at + 1] = value
