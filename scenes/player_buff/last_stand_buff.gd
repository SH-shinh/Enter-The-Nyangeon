extends Node2D

signal buff_time_out(buff: Buff)

@onready var buff_timer = $BuffTimer

@export var buff: Buff
@export var buff_id: String
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@export var is_remove_by_layer = false
@onready var check_timer: Timer = $CheckTimer

var num: int
var layer: int = 0
var is_stop: bool = false
var player: Node
var hurt_cd: int = 10
var now_cd: int = 0
var hurt_damage: int = 1
var first_life_num: int = 0

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	player.stats.hp_changed.connect(check_time_start)
	check_timer.timeout.connect(check_player_hp)
	GameEvents.player_buff_added.connect(on_buff_added)
	GameEvents.player_buff_clear.connect(clear_buff)
	GameEvents.round_end.connect(clear_buff)
	GameEvents.boss_round_end.connect(clear_buff)
	GameEvents.enemy_dead_hurt_damage.connect(kill_to_heal)

func on_buff_added(player_buff: Buff, current_buff: Dictionary):
	if player_buff.id != buff_id:
		return
	buff_timer.wait_time = buff_erase_timer
	buff_timer.start()
	num = current_buff[buff_id]["quantity"]
	
	if layer >= buff_layer:
		return
	if is_stop == true:
		return
	first_life_num = PlayerData.life_num_add
	PlayerData.life_num_add = 99999
	hurt_cd = buff_value
	hurt_damage = 11 - buff_value
	now_cd = hurt_cd
	layer += 1
	SoundManager.play_sfx("DeadSounds")
	PlayerData.update_player_ability()

func _physics_process(delta: float) -> void:
	if now_cd > 0:
		now_cd -= 1
		if now_cd <= 0:
			player.hurt_damage = hurt_damage
			player.hurt_knockback = 0
			player.is_buff_hurt = true
			player.emit_signal("is_hurt")
			now_cd = hurt_cd

func kill_to_heal(_hurt_damage: int):
	var heal_hp = player.stats.max_hp * 0.08
	player.health_hp = ceil(heal_hp)
	player.emit_signal("is_health")

func check_time_start():
	if check_timer.time_left <= 0 and player.stats.hp >= player.stats.max_hp:
		check_timer.start()

func check_player_hp():
	if is_stop == true:
		return
	if player.stats.hp >= player.stats.max_hp:
		SoundManager.play_sfx("EquipSounds3")
		clear_buff()

func timeout_check_player_hp():
	if player.stats.hp < player.stats.max_hp:
		GameEvents.emit_game_over(true)
	else:
		queue_free()

func _on_buff_timer_timeout():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		for i in layer:
			PlayerData.life_num_add = first_life_num
		layer = 0
	else:
		PlayerData.life_num_add = first_life_num
		layer -= 1
	PlayerData.update_player_ability()
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		timeout_check_player_hp()

func erase_buff(shoot_position: Node):
	if is_stop == true:
		return
	is_stop = true
	PlayerData.life_num_add = first_life_num
	layer = 0
	PlayerData.update_player_ability()
	if layer <= 0:
		buff_time_out.emit(buff)
		queue_free()

func clear_buff():
	if is_stop == true:
		return
	is_stop = true
	GameEvents.emit_player_buff_success(self)
	var heal_hp = player.stats.max_hp * 0.1
	player.health_hp = ceil(heal_hp)
	player.emit_signal("is_health")
	PlayerData.life_num_add = first_life_num
	layer = 0
	PlayerData.update_player_ability()
	if layer <= 0:
		buff_time_out.emit(buff)
		queue_free()
