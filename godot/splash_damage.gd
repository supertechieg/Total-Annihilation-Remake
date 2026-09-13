extends RefCounted
## Native blast-to-box falloff; damage dispatch and target enumeration are separate.

static func multiplier(point: Array, center: Array, lower: Array, upper: Array, radius: int, edge: float) -> float:
	var squared := 0.0
	for axis in range(3):
		var low := int(center[axis]) + int(lower[axis])
		var high := int(center[axis]) + int(upper[axis])
		var gap := maxi(low - int(point[axis]), maxi(int(point[axis]) - high, 0))
		squared += float(gap) * float(gap)
	var distance := int(sqrt(squared)) >> 16
	if distance >= radius:
		return 0.0
	if distance == 0:
		return 1.0
	var offset := float(distance) / float(radius) - 1.0
	var value := (1.0 - edge) * offset * offset + edge
	var encoded := PackedByteArray()
	encoded.resize(4)
	encoded.encode_float(0, value)
	return encoded.decode_float(0)
