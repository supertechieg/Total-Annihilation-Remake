extends Node2D
var combat: RefCounted
## Player group selection rings and the in-progress drag box (world coordinates).
var selected: Array = []
var box := Rect2()
## Drawn (height-lifted) unit position from the viewer; objects in 3D use z - (height >> 1).
var project_unit: Callable

func unit_point(id: int) -> Vector2:
	return project_unit.call(id) if project_unit.is_valid() else combat.world.units[id].position

static func flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z - float(int(floor(point.y)) >> 1))

func _draw() -> void:
	if combat == null:
		return
	for id in selected:
		if combat.world.units.has(int(id)):
			draw_arc(unit_point(int(id)), 16, 0, TAU, 32, Color("7dff7d"), 1.5)
	if box.size != Vector2.ZERO:
		draw_rect(box.abs(), Color(0.5, 1.0, 0.5, 0.12), true)
		draw_rect(box.abs(), Color("7dff7d"), false, 1.0)
	for id: int in combat.world.units:
		var unit: Dictionary = combat.world.units[id]
		if int(unit.get("team", 0)) != 0:
			var point: Vector2 = unit_point(id)
			draw_arc(point, 18, 0, TAU, 32, Color("ff6060"), 1.5)
			var maximum := float(combat.world.catalog.definition(unit.type).get("maxdamage", "1"))
			draw_line(point + Vector2(-16, -24), point + Vector2(16, -24), Color("402020"), 3)
			draw_line(point + Vector2(-16, -24), point + Vector2(-16 + 32 * float(unit.health) / maximum, -24), Color("ff6060"), 3)
	for projectile: Dictionary in combat.projectiles:
		var point: Vector3 = projectile.position
		if projectile.get("beam", false):
			# Development beam line from native tail to head; original palette colors/rendering are not reproduced.
			var tail: Vector3 = projectile.tail
			draw_line(flat(tail), flat(point), Color("ff5050"), 2.5)
			continue
		var previous: Vector3 = projectile.previous
		draw_line(flat(previous), flat(point), Color("fff0a0"), 2)
	for effect: Dictionary in combat.effects:
		var point: Vector3 = effect.position
		var frames: Array = combat.effect_assets.frames(str(effect.get("explosion", "")))
		if not frames.is_empty():
			var frame: Dictionary = frames[clampi(int(effect.duration) - int(effect.life), 0, frames.size() - 1)]
			var texture: Texture2D = combat.effect_assets.texture(str(frame.file))
			if texture != null:
				draw_texture(texture, flat(point) - Vector2(float(frame.x), float(frame.y)))
				continue
		draw_arc(flat(point), 10 - float(effect.life), 0, TAU, 16, Color(1, 0.6, 0.1, float(effect.life) / 8), 2)
