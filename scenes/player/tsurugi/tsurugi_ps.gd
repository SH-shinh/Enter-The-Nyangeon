extends Node2D

@export var player: Node
@export var stats: Stats
@export var second_gun: Node
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@export var damge_mult: Curve
@export var luck_value: Curve

var value: Array
var now_t:int
var count_damage: float = 0
var ammo_luck: float = 20
var heal_count: float = 0
var dead_num: int = 1

func _ready():
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.set_player.connect(set_playerdata)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.round_start.connect(reset_hurt_cd)
	stats.hp_changed.connect(count_bullet_damage)

func set_playerdata():
	PlayerData.max_ammo_value = 2

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		stats.hp_changed.connect(add_dead_buff)
		GameEvents.player_buff_success.connect(add_player_ability)
	elif now_t == 2:
		GameEvents.enemy_damage_taken.connect(count_enemy_distance_to_player)
	elif now_t == 3:
		GameEvents.enemy_damage_taken_dead.connect(add_ammo)

func count_bullet_damage():
	var n = float(stats.hp) / float(stats.max_hp)
	if count_damage != damge_mult.sample(n):
		PlayerData.bullet_damage_mult -= count_damage
		count_damage = damge_mult.sample(n)
		PlayerData.bullet_damage_mult += count_damage
		PlayerData.update_player_ability()

func add_player_ability(buff: Buff):
	if buff != null and buff == player_buff:
		PlayerData.bullet_damage_mult += 0.2
		PlayerData.bullet_penetrate_add += 2
		PlayerData.update_player_ability()

func reset_hurt_cd():
	dead_num = 1
	buff_value = 10
	PlayerData.heal_mult_add += heal_count
	heal_count = 0
	PlayerData.update_player_ability()

func count_enemy_distance_to_player(_final_damage: int, _damage_data: DamageData, body_path: NodePath):
	var hit_body: Node = get_node_or_null(body_path)
	if hit_body == null:
		return
	var value = clamp(hit_body.global_position.distance_to(player.global_position), 50, 150)
	var distance_damage_mult = 1.5 - value * 0.01
	hit_body.health_component.damage_multiplier += distance_damage_mult

func add_dead_buff():
	if player.stats.hp <= 0 and !player.player_buff_manager.current_buff.has(player_buff.id):
		player.player_buff_manager.apply_buff(player_buff, value)
		if buff_value > 1:
			buff_value = max(1, buff_value - 2)
		if dead_num <= 0:
			PlayerData.heal_mult_add -= 0.2
			heal_count += 0.2
			PlayerData.update_player_ability()
		dead_num -= 1

func add_ammo(_final_damage: int, _damage_data: DamageData, _body_path: NodePath):
	var luck = randf_range(0, 100)
	var n = float(stats.hp) / float(stats.max_hp)
	if luck < luck_value.sample(n):
		player.gun.now_bullet_ammo += 1
		second_gun.now_bullet_ammo += 1
	
