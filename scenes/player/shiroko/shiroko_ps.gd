extends Node2D

@export var stats: Stats
@export var player: Node
@export var drone: AbilityUpgrade
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var fire_diffuse = preload("res://scenes/debuff/fire_diffuse.tscn")

var value: Array
var diffuse_group: Array[Node]
var ps_luck: int = 70
var now_t:int
var index: int = 0
var critical_count: int = 0
var equip_count: float = 0

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.get_player.connect(add_shiroko_drone)
	GameEvents.equip_hit_enemy.connect(add_bullet_damage)
	GameEvents.round_upgrade.connect(reset_playerdata)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	match now_t:
		1:
			add_shiroko_drone()
			GameEvents.equip_kill_enemy.connect(equip_kill_count)
			buff_value = 2
			value = [buff_layer, buff_value, buff_erase_timer]
		2:
			add_shiroko_drone()
			GameEvents.enemy_critical_hurt.connect(critical_hurt_count)
		3:
			add_shiroko_drone()
			add_shiroko_drone()
			buff_value = 4
			value = [buff_layer, buff_value, buff_erase_timer]
			equipdamage_double()

func add_shiroko_drone():
	GameEvents.emit_add_player_upgrade(drone)

func add_bullet_damage(_enemy_body: Node, _bullet_body: Node):
	player.player_buff_manager.apply_buff(player_buff, value)

func reset_playerdata():
	if now_t > 0:
		PlayerData.critical_luck_add -= critical_count
		critical_count = 0
	
	if now_t > 1:
		PlayerData.equip_damage_mult -= equip_count
		equip_count = 0
	
	PlayerData.update_player_ability()

func equip_kill_count():
	critical_count += 1
	PlayerData.critical_luck_add += 1
	PlayerData.update_player_ability()

func critical_hurt_count(_enemy_body: Node):
	equip_count += 0.02
	PlayerData.equip_damage_mult += 0.02
	PlayerData.update_player_ability()

func equipdamage_double():
	PlayerData.equip_damage_mult *= 2
	PlayerData.update_player_ability()
