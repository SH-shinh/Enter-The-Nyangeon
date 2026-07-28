extends Node

enum Bus { MASTER, SFX, BGM, VOICE }

signal cut_finish
signal fade_out_end

@onready var sfx = $SFX
@onready var voice = $VOICE
@onready var talk: Node = $Talk
@onready var bgm_player = $BGM/BGMPlayer
@onready var animation_player: AnimationPlayer = $BGM/AnimationPlayer
@onready var voice_player: AudioStreamPlayer = $SupportVoice/VoicePlayer

var on_fade_out: bool = false
var game_end: bool = false

func play_sfx(name: String):
	var player := sfx.get_node(name) as AudioStreamPlayer
	if not player:
		return
	player.play()

func stop_sfx(name: String):
	var player := sfx.get_node(name) as AudioStreamPlayer
	if not player:
		return
	player.stop()

func play_support_voice(stream: AudioStream):
	if voice_player.playing:
		return
	voice_player.stream = stream
	voice_player.play()

func play_voice(player_name: String, type: String):
	var player := voice.get_node(player_name).get_node(type) as AudioStreamPlayer
	if not player:
		return
	player.play()

func play_talk(player_name: String, type: String):
	var player := talk.get_node(player_name).get_node(type) as AudioStreamPlayer
	if not player:
		return
	player.play()

func play_bgm_cut(stream: AudioStream):
	if bgm_player.stream == stream and bgm_player.playing:
		return
	if on_fade_out == true:
		await fade_out_end
	bgm_player.stream = stream
	bgm_player.play()
	await bgm_player.finished
	cut_finish.emit()

func play_bgm(stream: AudioStream):
	if bgm_player.stream == stream and bgm_player.playing:
		return
	if on_fade_out == true:
		await fade_out_end
	bgm_player.stream = stream
	bgm_player.play()

func bgm_fade_out():
	on_fade_out = true
	animation_player.play("1s")
	await animation_player.animation_finished
	on_fade_out = false
	bgm_player.stop()
	bgm_player.volume_db = linear_to_db(1)
	fade_out_end.emit()

func bgm_slow_fade_out(stream: AudioStream):
	on_fade_out = true
	animation_player.play("4s")
	await animation_player.animation_finished
	if game_end == true:
		return
	on_fade_out = false
	bgm_player.stop()
	bgm_player.volume_db = linear_to_db(1)
	fade_out_end.emit()
	play_bgm_cut(stream)

func get_volume(bus_index: int):
	var db := AudioServer.get_bus_volume_db(bus_index)
	return db_to_linear(db)

func set_volume(bus_index: int, v: float):
	var db := linear_to_db(v)
	AudioServer.set_bus_volume_db(bus_index, db)
