extends Node2D

@export var player: Node
@export var stats: Stats
@export var gun: Node

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var now_t:int
var value: Array
var critical_damage_count: float = 0
var critical_luck_count: int = 0

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.player_ammo_reload.connect(add_player_luck_buff)
	GameEvents.enemy_damage_taken_dead.connect(add_fast_reload)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		PlayerData.critical_luck_add += 15
		PlayerData.update_player_ability()
		PlayerData.player_ability_changed.connect(fire_rate_count)
	elif now_t == 2:
		buff_value = 8
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.critical_luck_add += 15
		PlayerData.update_player_ability()
		GameEvents.enemy_damage_taken_dead.connect(critical_kill_enemy)
	elif now_t == 3:
		buff_value = 15
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.critical_luck_add += 15
		PlayerData.update_player_ability()
		PlayerData.player_ability_changed.connect(critical_luck_to_damage)

func add_fast_reload(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if gun.now_bullet_ammo <= 0 and damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		PoolManager.add_text("RELOAD!", player.global_position, Color(1,1,1), 16)
		SoundManager.play_sfx("ReloadSounds")
		gun.reload_ammo()
		GameEvents.emit_player_ammo_reload(gun.now_bullet_ammo, stats.max_ammo, 0.1)

func add_player_luck_buff(_now_ammo: float, _max_ammo: int, _reload_time: float):
	player.player_buff_manager.apply_buff(player_buff, value)

func fire_rate_count():
	var n = player.stats.critical_luck * 0.01
	if critical_damage_count != n:
		PlayerData.bullet_shoot_time_mult -= critical_damage_count
		critical_damage_count = n
		PlayerData.bullet_shoot_time_mult += critical_damage_count
		PlayerData.update_player_ability()

func critical_kill_enemy(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.is_crit == true and damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		PlayerData.bullet_damage_mult += 0.01
		PlayerData.update_player_ability()

func critical_luck_to_damage():
	var n:int = max(0, PlayerData.base_critical_luck + PlayerData.critical_luck_add ) * PlayerData.critical_luck_mult * PlayerData.ability_mult
	n -= 100
	if n > 0 and critical_luck_count != n:
		var x = critical_luck_count * 0.02
		PlayerData.critical_damage_add -= x
		critical_luck_count = n
		x = critical_luck_count * 0.02
		PlayerData.critical_damage_add += x
		PlayerData.update_player_ability()
