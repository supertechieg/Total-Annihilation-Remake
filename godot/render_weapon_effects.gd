extends SceneTree
const Overlay = preload("res://combat_overlay.gd")
const Assets = preload("res://weapon_effects.gd")
class Fixture extends RefCounted:
	var world := {"units": {}}
	var projectiles: Array = []
	var effects: Array = []
	var effect_assets: RefCounted

func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	root.size = Vector2i(720, 480)
	root.content_scale_size = Vector2i(720, 480)
	var background := ColorRect.new()
	background.color = Color("253b35")
	background.size = Vector2(720, 480)
	root.add_child(background)
	var fixture := Fixture.new()
	fixture.effect_assets = Assets.new(ProjectSettings.globalize_path("res://../local/weapon-effects/"))
	var overlay := Overlay.new()
	overlay.combat = fixture
	root.add_child(overlay)
	var row := 0
	for key in ["fx/explode2", "fx/explode3", "fx/explode4", "fx/explode5"]:
		var frames: Array = fixture.effect_assets.frames(key)
		if frames.is_empty():
			quit(1)
			return
		var label := Label.new()
		label.text = key + " — first / middle / last"
		label.position = Vector2(12, row * 120 + 8)
		root.add_child(label)
		var column := 0
		for frame_index in [0, int(frames.size() / 2), frames.size() - 1]:
			fixture.effects.append({"position": Vector3(260 + column * 170, 0, row * 120 + 75),
				"duration": frames.size(), "life": frames.size() - frame_index, "explosion": key})
			column += 1
		row += 1
	overlay.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://../local/weapon-effects/overlay-preview.png")
	var error := image.save_png(path)
	print("WEAPON_EFFECT_RENDER ", path, " error=", error)
	quit(0 if error == OK else 1)
