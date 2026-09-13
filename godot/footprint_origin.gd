extends RefCounted

static func axis(raw_position: int, size: int) -> int:
	var raw := (raw_position - size * 0x80000 + 0x80000) & 0xffffffff
	if raw >= 0x80000000:
		raw -= 0x100000000
	return raw >> 20
