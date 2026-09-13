extends Node
const Sounds = preload("res://weapon_sounds.gd")
var sounds := Sounds.new(ProjectSettings.globalize_path("res://../local/weapon-sounds/"))
var players: Array[AudioStreamPlayer] = []
var cursor := 0
var played := 0

func play_sound(name: String, _position: Vector3) -> void:
	# Verification runs simulate faster than wall time; do not play their audio.
	if DisplayServer.get_name() == "headless":
		return
	var stream := sounds.sound(name)
	if stream == null:
		return
	var player: AudioStreamPlayer
	for candidate in players:
		if not candidate.playing:
			player = candidate
			break
	if player == null and players.size() < 32:
		player = AudioStreamPlayer.new()
		player.volume_db = -12.0
		add_child(player)
		players.append(player)
	if player == null:
		player = players[cursor % players.size()]
		cursor += 1
	player.stream = stream
	player.play()
	played += 1
