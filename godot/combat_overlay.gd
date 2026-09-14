extends Node2D
var combat: RefCounted
## Player group selection rings and the in-progress drag box (world coordinates).
var selected: Array = []
var box := Rect2()

func _draw() -> void:
	if combat == null:
		return
	for id in selected:
		if combat.world.units.has(int(id)):
			draw_arc(combat.world.units[int(id)].position, 16, 0, TAU, 32, Color("7dff7d"), 1.5)
	if box.size != Vector2.ZERO:
		draw_rect(box.abs(), Color(0.5, 1.0, 0.5, 0.12), true)
		draw_rect(box.abs(), Color("7dff7d"), false, 1.0)
	for unit: Dictionary in combat.world.units.values():
		if int(unit.get("team", 0)) != 0:
			var point: Vector2 = unit.position
			draw_arc(point, 18, 0, TAU, 32, Color("ff6060"), 1.5)
			var maximum := float(combat.world.catalog.definition(unit.type).get("maxdamage", "1"))
			draw_line(point + Vector2(-16, -24), point + Vector2(16, -24), Color("402020"), 3)
			draw_line(point + Vector2(-16, -24), point + Vector2(-16 + 32 * float(unit.health) / maximum, -24), Color("ff6060"), 3)
	for projectile: Dictionary in combat.projectiles:
		var point: Vector3 = projectile.position
		if projectile.get("beam", false):
			# Development beam line from native tail to head; original palette colors/rendering are not reproduced.
			var tail: Vector3 = projectile.tail
			draw_line(Vector2(tail.x, tail.z), Vector2(point.x, point.z), Color("ff5050"), 2.5)
			continue
		var previous: Vector3 = projectile.previous
		draw_line(Vector2(previous.x, previous.z), Vector2(point.x, point.z), Color("fff0a0"), 2)
	for effect: Dictionary in combat.effects:
		var point: Vector3 = effect.position
		var frames: Array = combat.effect_assets.frames(str(effect.get("explosion", "")))
		if not frames.is_empty():
			var frame: Dictionary = frames[clampi(int(effect.duration) - int(effect.life), 0, frames.size() - 1)]
			var texture: Texture2D = combat.effect_assets.texture(str(frame.file))
			if texture != null:
				draw_texture(texture, Vector2(point.x - float(frame.x), point.z - float(frame.y)))
				continue
		draw_arc(Vector2(point.x, point.z), 10 - float(effect.life), 0, TAU, 16, Color(1, 0.6, 0.1, float(effect.life) / 8), 2)
