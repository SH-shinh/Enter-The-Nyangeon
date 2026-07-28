extends CanvasLayer

@export var enemy_buff: Buff

@onready var now_round = $Control/NowRound
@onready var timer = $Control/Timer
@onready var minute_show = $Control/HBoxContainer/MinuteShow
@onready var second_show = $Control/HBoxContainer/SecondShow
@onready var millisecond_show = $Control/HBoxContainer/MillisecondShow
@onready var animation_player = $AnimationPlayer
@onready var time_bar = $%TimeBar
@onready var round_timer = $RoundTimer
@onready var global_timer = $GlobalTimer

@onready var fever_anim_1: AnimationPlayer = $FeverTime/AnimationPlayer
@onready var fever_anim_2: AnimationPlayer = $FeverTime/AnimationPlayer2

var is_boss_round: bool = false
var rage_mode: bool = false
var boss_group: Array
var value: Array = [999, 0.05, 99999]
var rage_time: int = 0

var time_mult: float = 1
var is_game_mode_1: bool = false

signal round_start
signal round_end
signal round_time_warning
signal round_time_out

var now_round_num = 0:
	set(v):
		now_round_num = v
		now_round.text = "ROUND %s" % [str(v) ]
		GameEvents.emit_round_num_changed(now_round_num)
		PlayerData.now_round = now_round_num

var round_time = 0:
	set(v):
		round_time = v
		if floor(v / 60 ) < 10:
			minute_show.text = str( "0",str(floor(v / 60 )),":")
		else:
			minute_show.text = str( str(floor(v / 60 )),":")
		if v - (floor(v / 60 ) * 60 ) < 10:
			second_show.text = str("0", str(v - (floor(v / 60 ) * 60 )),":")
		else:
			second_show.text = str( str(v - (floor(v / 60 ) * 60 )),":")
		if v < 10:
			emit_signal("round_time_warning")

func _ready():
	GameEvents.round_start.connect(init_round)
	GameEvents.boss_round_start.connect(boss_round)
	GameEvents.boss_round_end.connect(rage_mode_end)
	GameEvents.pyroxenes_pick_up.connect(end_boss_round)
	GameEvents.game_over.connect(game_over_stop)
	GameEvents.ui_visible.connect(game_ui_visible)
	GameEvents.fever_time_start.connect(play_fever_anim)

func game_ui_visible(now_visible: bool):
	visible = now_visible

func _physics_process(delta):
	
	time_bar.value = round_timer.time_left / round_timer.wait_time
	if int(timer.time_left * 100) < 10:
		millisecond_show.text = str("0",int(timer.time_left * 100))
	else:
		millisecond_show.text = str(int(timer.time_left * 100))

func boss_round():
	is_boss_round = true
	round_time = 60 * time_mult + 29
	round_timer.wait_time = 90
	timer.start()
	round_timer.start()

func init_round():
	now_round_num += 1
	round_time = 60 * time_mult - 1
	round_timer.wait_time = 60
	timer.start()
	round_timer.start()
	global_timer.start()
	$Control/NowRound.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/Label.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/MinuteShow.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/SecondShow.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/MillisecondShow.set("theme_override_colors/font_color", Color(1, 1, 1))

func game_over_stop(player_dead: bool):
	SoundManager.game_end = true
	timer.stop()
	global_timer.stop()
	round_timer.stop()

func _on_timer_timeout():
	
	if rage_mode == false:
		round_time -=1
		if round_time <= 0:
			if is_boss_round == false:
				await get_tree().create_timer(0.9).timeout
				timer.stop()
				round_time_out.emit()
				GameEvents.emit_round_end()
			else:
				if PlayerData.game_mode.has("hujiu"):
					timer.stop()
					round_time_out.emit()
					GameEvents.emit_round_end()
				else:
					round_time_out.emit()
					rage_mode = true
					boss_group = get_tree().get_nodes_in_group("BOSS")
					GameEvents.emit_fever_time_start()
	else:
		round_time += 1
		rage_time += 1
		if rage_time > 5:
			rage_time = 0
			add_rage_buff()

func add_rage_buff():
	if boss_group.size() > 0:
		for i in boss_group.size():
			boss_group[i].enemy_buff_manager.apply_buff(enemy_buff, value)

func rage_mode_end():
	is_boss_round = false
	rage_mode = false
	timer.stop()

func end_boss_round():
	await get_tree().create_timer(3.5).timeout
	GameEvents.emit_round_end()

func set_font_red():
	$Control/NowRound.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/Label.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/MinuteShow.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/SecondShow.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/MillisecondShow.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))

func play_fever_anim():
	fever_anim_1.play("fever_time")
	fever_anim_2.play("fever_anim")
	SoundManager.play_sfx("WarringSounds")

func _on_round_time_warning():
	if rage_mode == false:
		animation_player.play("new_animation")
	else:
		set_font_red()


func _on_round_time_out():
	set_font_red()

func cleanup_orphaned_nodes(node: Node):
	var child_count = node.get_child_count()
	for i in range(child_count):
		var child = node.get_child(i)
		cleanup_orphaned_nodes(child)
	if node.get_parent() == null:
		print("Found orphaned node: ", node.name)
		node.queue_free()

func _on_global_timer_timeout():
	GameEvents.emit_global_time_count()
