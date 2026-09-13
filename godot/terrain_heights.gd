extends RefCounted
## Original full-map 0x483210 extrema update into initially zeroed fields.
static func prepare(data: PackedByteArray, width: int, height: int) -> Dictionary:
	var low := PackedByteArray()
	var high := PackedByteArray()
	low.resize(width * height)
	high.resize(width * height)
	for y in range(height - 1):
		for x in range(width - 1):
			var index := y * width + x
			low[index] = mini(mini(data[index], data[index + 1]), mini(data[index + width], data[index + width + 1]))
			high[index] = maxi(maxi(data[index], data[index + 1]), maxi(data[index + width], data[index + width + 1]))
	return {"low": low, "high": high}
