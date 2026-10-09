extends CanvasLayer

signal transition_start

@export var bgm_loop: AudioStream
@export var bgm_cut_win: AudioStream
@export var bgm_loop_win: AudioStream
@export var up_item_card: PackedScene
@export_file("*.tscn") var path: String

@onready var card_box = %card_box
@onready var round_num = %RoundNum
@onready var score_num = %ScoreNum
@onready var time_num = %TimeNum
@onready var defeats_num = %DefeatsNum
@onready var coins_num = %CoinsNum
@onready var time_count = $TimeCount
@onready var animation_player = $AnimationPlayer
@onready var return_button = %ReturnButton
@onready var player_color = $Node2D3/Node2D/Node2D6/ColorRect/PlayerColor
@onready var player_p = %PlayerP
@onready var player_halo = %PlayerHalo
@onready var player_name = %PlayerName
@onready var player_weapon = %PlayerWeapon
@onready var motion_screen = $MotionScreen
@onready var player_id_input: Control = $player_id_input

var second: int = 0
var minute: int = 0
var hour: int = 0

var score: int = 0
var defeats: int = 0
var coins: int = 0

var on_touch: bool = false

var current_card: Dictionary = {}

var player: Node

var is_return_selected: bool = false

var is_win: bool = false

func _ready():
	GameEvents.ability_upgrade_added.connect(add_player_up_item_card)
	GameEvents.round_num_changed.connect(end_round_num)
	GameEvents.get_player.connect(get_player)
	GameEvents.first_round_add.connect(time_count_start)
	GameEvents.game_over.connect(time_count_stop)
	GameEvents.enemy_dead_score.connect(score_defeats_count)
	GameEvents.player_coins_get.connect(coins_count)
	GameEvents.player_stats_coin_cost.connect(coins_cost_count)
	GameEvents.player_card_touch.connect(tounch_out)
	return_button.mouse_entered.connect(return_mouse_in)
	return_button.mouse_exited.connect(return_mouse_out)
	return_button.gui_input.connect(return_selected)
	SoundManager.cut_finish.connect(play_win_loop)
	GameEvents.player_id_print.connect(print_player_score)

func print_player_score(player_id: String):
	var record: Dictionary = {
		"date": Time.get_datetime_dict_from_system(),
		"player_id" : player_id,
		"level" : PlayerData.level_id,
		"score" : score,
		"player" : PlayerData.player_select,
		"support" : SupportData.game_support.support_id if SupportData.game_support != null else "null",
		"round" : round_num.text,
		"defeats" : defeats,
		"coins" : coins,
		"time" : str(hour) + ":" + str(minute) + ":" + str(second),
		"game_mode" : PlayerData.game_mode,
		"is_win" : is_win,
		"equip" : PlayerData.current_upgrades,
		}
	Game.save_record_as_json("user://scorebound/game_score.json", record)

func coins_count(coins_value):
	coins += coins_value
	score += coins_value * 2

func coins_cost_count(coins_value):
	score -= coins_value * 2

func score_defeats_count(body_score):
	score += round(body_score * PlayerData.level_score_mult)
	defeats += 1

func emit_transition_start():
	transition_start.emit()

func button_open():
	return_button.mouse_filter = 0

func button_close():
	return_button.mouse_filter = 2

func time_count_start():
	time_count.start()

func time_count_stop(player_dead: bool):
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player_dead == true:
		is_win = false
		SoundManager.play_sfx("GameOver")
		motion_screen.material.set_shader_parameter("grayscale", true)
	else:
		is_win = true
		SoundManager.play_sfx("Win")
		$Node2D2/AnimationPlayer.play("win_anim")
		motion_screen.material.set_shader_parameter("grayscale", false)
	SoundManager.bgm_fade_out()
	$AnimationPlayer2.play("motion_anim")
	time_count.stop()
	var tween = create_tween()
	tween.tween_property(Engine, "time_scale", 0.1, 0.5).from(1)
	await tween.finished
	Engine.time_scale = 1
	get_tree().paused = true
	if player_dead == true:
		SoundManager.play_bgm(bgm_loop)
	else:
		SoundManager.play_bgm_cut(bgm_cut_win)
	animation_player.play("game_over_in")
	time_num.text = str(hour) + ":" + str(minute) + ":" + str(second)
	score_num.text = str(score)
	defeats_num.text = str(defeats)
	coins_num.text = str(coins)
	if player_dead == true:
		player_p.frame = 3
		play_voice("LoseVoice")
	else:
		player_p.frame = 2
		play_voice("WinVoice")
	await animation_player.animation_finished
	player_id_input.input_screen_show()
	button_open()

func play_voice(name_local: String):
	var n = randi_range(0,1)
	if n == 0:
		SoundManager.play_voice(player.player_card.voice_name, name_local + str(n + 1))
	else:
		SoundManager.play_voice(player.player_card.voice_name, name_local + str(n + 1))

func play_win_loop():
	SoundManager.play_bgm(bgm_loop_win)

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	player_color.color = player.player_card.color
	player_p.texture = LazyTexture.load_uncached(player.player_card.sprite_path)
	player_halo.texture = player.player_card.halo
	player_name.text = player.player_card.name
	player_weapon.text = player.player_card.weapon
	player_weapon.set("theme_override_colors/font_color", player.player_card.color)

func end_round_num(now_round_num: int):
	round_num.text = str(now_round_num)

func card_anim():
	var cards = card_box.get_children()
	if cards.is_empty():
		return
	
	for i in cards.size():
		cards[i].visible = false
	
	for i in cards.size():
		var tween = create_tween()
		cards[i].visible = true
		tween.tween_property(cards[i],"scale",Vector2(1.1,1.1),0.07).from(Vector2(0,0))
		tween.chain()
		tween.tween_property(cards[i],"scale",Vector2(1,1),0.03).from(Vector2(1.1,1.1))
		await tween.finished

func add_player_up_item_card(upgrade: AbilityUpgrade, _current_upgrade: Dictionary):
	var has_card = current_card.has(upgrade.id)
	if !has_card:
		current_card[upgrade.id] = {
			"resource": upgrade
		}
		var card_ins = up_item_card.instantiate()
		card_box.add_child(card_ins)
		card_ins.set_up_item_card(upgrade)

func return_mouse_in():
	if is_return_selected == false:
		$Node2D3/Node2D3/Node2D6/ReturnButton/AnimationPlayer.play("mouse_in")

func return_mouse_out():
	if is_return_selected == false:
		$Node2D3/Node2D3/Node2D6/ReturnButton/AnimationPlayer.play("mouse_out")

func tounch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_touch == true:
		on_touch = false
		if is_return_selected == false:
			$Node2D3/Node2D3/Node2D6/ReturnButton/AnimationPlayer.play("mouse_out")


func return_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			if is_return_selected == false:
				$Node2D3/Node2D3/Node2D6/ReturnButton/AnimationPlayer.play("mouse_in")
			
		else:
			if is_return_selected == false:
				SoundManager.play_sfx("ButtonSounds")
				is_return_selected = true
				$Node2D3/Node2D3/Node2D6/ReturnButton/AnimationPlayer.play("selected")
				await transition_start
				SoundManager.bgm_fade_out()
				Transition.play_left_start()
				await Transition.left_end_start
				get_tree().paused = false
				GameEvents.change_scene(path,"")
	
	if event.is_action_pressed("shoot") and is_return_selected == false:
		SoundManager.play_sfx("ButtonSounds")
		is_return_selected = true
		$Node2D3/Node2D3/Node2D6/ReturnButton/AnimationPlayer.play("selected")
		await transition_start
		SoundManager.bgm_fade_out()
		Transition.play_left_start()
		await Transition.left_end_start
		get_tree().paused = false
		GameEvents.change_scene(path,"")

func _on_time_count_timeout():
	second += 1
	if second > 59:
		second = 0
		minute += 1
		if minute > 59:
			minute = 0
			hour += 1
