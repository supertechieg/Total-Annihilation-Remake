extends SceneTree
const Audio = preload("res://weapon_audio.gd")
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	audio.enabled = true
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	var checks: Array = []
	audio.play_sound("canlite3", Vector3.ZERO)
	checks.append(audio.played == 1 and audio.players.size() == 1 and audio.players[0].playing)
	await create_timer(0.4).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	checks.append(samples.size() > 0 and peak > 0.0)
	for player in audio.players:
		player.stop()
	audio.play_sound("canlite3", Vector3.ZERO)
	checks.append(audio.players.size() == 1)
	for i in range(40):
		audio.play_sound("canlite3", Vector3.ZERO)
	checks.append(audio.players.size() == 32 and audio.played == 42)
	var before := audio.played
	audio.enabled = false
	audio.play_sound("canlite3", Vector3.ZERO)
	checks.append(audio.played == before)
	AudioServer.remove_bus_effect(0, slot)
	var report := {"checks": checks.size(), "failures": checks.count(false), "captured_frames": samples.size(), "peak": peak,
		"scope": "Original cannon WAV mixed to AudioEffectCapture, idle voice reuse, 32-voice cap and disabled playback; excludes physical speaker output and native audio fidelity"}
	FileAccess.open("res://../analysis/weapon-playback-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("WEAPON_PLAYBACK %d / %d checks pass; captured=%d peak=%f" % [checks.size() - checks.count(false), checks.size(), samples.size(), peak])
	for player in audio.players:
		player.stop()
	audio.free()
	capture = null
	await process_frame
	quit(0 if checks.count(false) == 0 else 1)
