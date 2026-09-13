extends RefCounted
## Original static Boolean-terrain aggregation: 0 blocked, 1 fits, 3 clear border.
static func prepare(allowed: PackedByteArray, width: int, height: int, footprint: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(width * height)
	# Prefix sums count blocked cells in each rectangle without rescanning footprints.
	var stride := width + 1
	var sums := PackedInt32Array()
	sums.resize(stride * (height + 1))
	for y in range(height):
		var row := 0
		for x in range(width):
			row += int(allowed[y * width + x] == 0)
			sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row
	for y in range(height):
		for x in range(width):
			var right := x + footprint.x
			var bottom := y + footprint.y
			if right > width or bottom > height or blocked_count(sums, stride, x, y, right, bottom) != 0:
				continue
			result[y * width + x] = 1
			if x > 0 and y > 0 and right < width and bottom < height and blocked_count(sums, stride, x - 1, y - 1, right + 1, bottom + 1) == 0:
				result[y * width + x] = 3
	return result

static func blocked_count(sums: PackedInt32Array, stride: int, left: int, top: int, right: int, bottom: int) -> int:
	return sums[bottom * stride + right] - sums[top * stride + right] - sums[bottom * stride + left] + sums[top * stride + left]
