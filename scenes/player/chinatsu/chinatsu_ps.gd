extends PlayerPS

signal charge_changed(value: int)

const MAX_CHARGE: int = 10
const SYRINGE_ABILITY: float = 0.2
const SYRINGE_TIME: float = 5.0
const SYRINGE_MAX_LAYER: int = 99
const T1_BUFF_MAX_LAYER: int = 1
const T1_BUFF_VALUE: float = 0.5
const GLOBAL_DAMAGE_PER_BUFF: float = 0.2
const T2_CHARGE_PER_MEDKIT: int = 2
const T2_REFUND_CHANCE: float = 0.5
const T3_BUFF_LAYER_MULT_ADD: float = 1.0
const VULN_PER_LAYER: float = 0.1
const VULN_TIME: float = 5.0
const VULN_MAX_LAYER: int = 999

@export var ability_buff: Buff = preload("res://resources/buff/player_buff/chinatsu_ability_buff.tres")
@export var fire_rate_buff: Buff = preload("res://resources/buff/player_buff/chinatsu_fire_rate_buff.tres")
@export var move_speed_buff: Buff = preload("res://resources/buff/player_buff/chinatsu_move_speed_buff.tres")
@export var vuln_buff: Buff = preload("res://resources/buff/enemy_buff/chinatsu_vuln_buff.tres")
@export var neddle_anim: Node

@onready var charge_count: Node2D = get_node_or_null("ChargeCount")
@onready var charge_label: Label = get_node_or_null("ChargeCount/Label")

var charge: int = 0
var _buff_damage: float = 0.0
var _t1_active: bool = false
var _t2_active: bool = false
var _t3_active: bool = false
var _t3_applied: bool = false

func _ready():
	super._ready()
	GameEvents.player_taken_medkit.connect(add_charge)
	PlayerData.set_player.connect(_on_set_player)
	PlayerData.reset_done.connect(_reset_contrib)
	_update_charge_ui()

func _physics_process(_delta):
	if charge_count != null and player != null:
		charge_count.position.y = player.sprite_2d.position.y - 13

func _on_set_player():
	_t1_active = now_t >= 1
	_t2_active = now_t >= 2
	_t3_active = now_t >= 3
	if not _t1_active:
		return
	var manager: Node = player.player_buff_manager
	if manager == null:
		return
	if not manager.buff_applied.is_connected(_recount):
		manager.buff_applied.connect(_recount)
		manager.buff_consumed.connect(_recount)
	if not manager.buff_expired.is_connected(_on_buff_expired):
		manager.buff_expired.connect(_on_buff_expired)
	if _t3_active and not _t3_applied:
		_t3_applied = true
		PlayerData.buff_layer_mult_add += T3_BUFF_LAYER_MULT_ADD
		PlayerData.update_player_ability()
	if _t3_active and not GameEvents.enemy_damage_taken.is_connected(_on_enemy_damage_taken):
		GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)
	_recount()

func ps_upgrade(t_num: int):
	now_t = t_num
	_on_set_player()

func add_charge(_taken_position: Vector2 = Vector2.ZERO):
	if charge >= MAX_CHARGE:
		return
	var amount: int = T2_CHARGE_PER_MEDKIT if _t2_active else 1
	charge = min(charge + amount, MAX_CHARGE)
	SoundManager.play_sfx("PowerUp1")
	charge_changed.emit(charge)
	_update_charge_ui()

func on_melee_use():
	if charge <= 0:
		return
	charge -= 1
	charge_changed.emit(charge)
	_update_charge_ui()
	if neddle_anim != null:
		neddle_anim.play_anim()
	var manager: Node = player.player_buff_manager
	if manager == null:
		return
	manager.apply_buff(ability_buff, [SYRINGE_MAX_LAYER, SYRINGE_ABILITY, SYRINGE_TIME])
	if now_t >= 1:
		manager.apply_buff(fire_rate_buff, [T1_BUFF_MAX_LAYER, T1_BUFF_VALUE, SYRINGE_TIME])
		manager.apply_buff(move_speed_buff, [T1_BUFF_MAX_LAYER, T1_BUFF_VALUE, SYRINGE_TIME])

func _on_buff_expired(_buff: Buff):
	if _t1_active:
		_recount()
	if _t2_active and randf() < T2_REFUND_CHANCE and charge < MAX_CHARGE:
		charge += 1
		charge_changed.emit(charge)
		_update_charge_ui()

func _recount(_a = null, _b = null):
	if not _t1_active:
		return
	var manager: Node = player.player_buff_manager
	if manager == null:
		return
	var target: float = manager.current_buff.size() * GLOBAL_DAMAGE_PER_BUFF
	var delta: float = target - _buff_damage
	if is_zero_approx(delta):
		return
	_buff_damage = target
	PlayerData.global_damage_mult += delta
	PlayerData.update_player_ability()

func _on_enemy_damage_taken(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if not _t3_active or damage_data == null:
		return
	if not damage_data.source_type.has(GameTags.PLAYER):
		return
	if not damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		return
	var enemy = get_node_or_null(body_path)
	if enemy == null:
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	var count: int = player.player_buff_manager.current_buff.size()
	if count <= 0:
		return
	var layers_now: int = 0
	if manager.current_buff.has(vuln_buff.id):
		layers_now = int(manager.current_buff[vuln_buff.id]["layer"])
	var add_layers: int = count - layers_now
	if add_layers > 0:
		for i in add_layers:
			manager.apply_buff(vuln_buff, [VULN_MAX_LAYER, VULN_PER_LAYER, VULN_TIME])
	else:
		manager.refresh_buff(vuln_buff.id)

func _update_charge_ui():
	if charge_label != null:
		charge_label.text = "%d\n--\n%d" % [charge, MAX_CHARGE]

func _reset_contrib():
	_buff_damage = 0.0
	_t3_applied = false


# 联机：镜像回放充能计数（只改 Label，不改 charge 玩法值）
func get_network_character_state() -> int:
	return int(charge) & 0xF


func apply_network_character_state(state: int) -> void:
	var c: int = state & 0xF
	if charge_label != null:
		charge_label.text = "%d\n--\n%d" % [c, MAX_CHARGE]
