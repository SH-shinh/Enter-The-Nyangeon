extends PlayerPS


const ENERGY_BUFF: Buff = preload("res://resources/buff/player_buff/aris_energy_buff.tres")


@export var max_energy_per_tier: float = 25.0
@export var regen_per_tier: float = 5.0
@export var hit_energy_gain: float = 1.0
@export var hit_cooldown: float = 0.1

@export var energy_per_stack: float = 10.0
@export var laser_tick_mult_t1: float = 0.6
@export var laser_tick_mult_t2: float = 0.8
@export var laser_tick_mult_t3: float = 1.2
@export var buff_max_layer: int = 99
@export var buff_duration: float = 9999.0


var base_max_energy: float
var base_regen_rate: float
var _last_hit_time: Dictionary = {}
var upgrade_t: int = 0

var crit_energy_gain: bool = false

var _pending_energy: float = 0.0

func _ready() -> void:
	super._ready()
	base_max_energy = player.max_energy
	base_regen_rate = player.energy_regen_rate
	if player.has_signal("energy_spent"):
		player.energy_spent.connect(_on_energy_spent)
	GameEvents.round_end.connect(_reset_energy_buff)


func ps_upgrade(t_num: int) -> void:
	super.ps_upgrade(t_num)
	match now_t:
		1:
			GameEvents.enemy_damage_taken.connect(_on_bullet_hit_enemy)
			upgrade_t = 1
		2:
			upgrade_t = 2
		3:
			upgrade_t = 4
			crit_energy_gain = true
	
	_apply_tier()
	_apply_laser_mult()


func _apply_tier() -> void:
	player.max_energy = base_max_energy + max_energy_per_tier * upgrade_t
	player.energy_regen_rate = base_regen_rate + regen_per_tier * now_t


func _apply_laser_mult() -> void:
	if gun == null or gun.get("laser_tick_mult") == null:
		return
	match now_t:
		1:
			gun.laser_tick_mult = laser_tick_mult_t1
		2:
			gun.laser_tick_mult = laser_tick_mult_t2
		3:
			gun.laser_tick_mult = laser_tick_mult_t3


func _on_energy_spent(amount: float) -> void:
	if now_t < 2 or amount <= 0.0:
		return
	_pending_energy += amount
	var stacks_per_threshold: int = 2 if now_t >= 3 else 1
	var manager: Node = player.get("player_buff_manager")
	if manager == null:
		return
	while _pending_energy >= energy_per_stack:
		_pending_energy -= energy_per_stack
		for i in stacks_per_threshold:
			manager.apply_buff(ENERGY_BUFF, [buff_max_layer, 1, buff_duration])


func _reset_energy_buff() -> void:
	_pending_energy = 0.0
	# 命中时间表以敌人 instance_id 为 key、只增不减；回合结束清理防长局无界增长。
	_last_hit_time.clear()
	if player != null and player.get("player_buff_manager") != null:
		player.player_buff_manager.remove_buff(ENERGY_BUFF)


func _on_bullet_hit_enemy(_final_damage: int, damage_data: DamageData, body_path: NodePath) -> void:
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE) and damage_data.source_type.has(GameTags.PLAYER):
		var hit_body: Node = get_node(body_path)
		if hit_body == null:
			return
		var id := hit_body.get_instance_id()
		var now := Time.get_ticks_msec()
		var last: int = _last_hit_time.get(id, 0)
		if now - last < int(hit_cooldown * 1000.0):
			return
		_last_hit_time[id] = now
		player.add_energy(hit_energy_gain)
		if crit_energy_gain and damage_data.is_crit:
			player.add_energy(hit_energy_gain)
