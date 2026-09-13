extends RefCounted
## Provisional unrotated yard overlay; native occupancy rules remain to be compared.

static func overlay(nav: RefCounted, terrain: PackedByteArray, units: Dictionary, catalog: RefCounted, scripts: Dictionary, footprint: Vector2i) -> void:
	nav.blocked = terrain.duplicate()
	for unit: Dictionary in units.values():
		var fields: Dictionary = catalog.definition(unit.type)
		if int(fields.get("bmcode", "1")) != 0:
			continue
		var width := int(fields.get("footprintx", "1"))
		var height := int(fields.get("footprintz", "1"))
		var origin: Vector2 = unit.position - Vector2(width, height) * 8
		var yard := str(fields.get("yardmap", "")).replace(" ", "").replace("\n", "").replace("\r", "")
		var opened := scripts.has(unit.id) and int(scripts[unit.id].values.get(18, 0)) != 0
		for y in range(height):
			for x in range(width):
				var symbol := yard[y * width + x] if yard.length() == width * height else "o"
				if float(unit.remaining) == 0 and (symbol in ["y", "."] or (opened and symbol == "c")):
					continue
				var tile := Rect2(origin + Vector2(x, y) * 16, Vector2(16, 16))
				for cy in range(maxi(0, int(tile.position.y / 16) - footprint.y), mini(nav.height, int(tile.end.y / 16) + footprint.y + 1)):
					for cx in range(maxi(0, int(tile.position.x / 16) - footprint.x), mini(nav.width, int(tile.end.x / 16) + footprint.x + 1)):
						var size := Vector2(footprint) * 16
						if tile.intersects(Rect2(Vector2(cx, cy) * 16 - size * 0.5, size)):
							nav.blocked[cy * nav.width + cx] = 1
