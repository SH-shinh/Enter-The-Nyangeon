extends PlayerPS

@export var sniper_bullet: PackedScene

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@export var cross_bullet: PackedScene

@onready var charge_up: Timer = $ChargeUP
@onready var gpu_particles_2d: GPUParticles2D = $"../Graphics/Gun/GPUParticles2D"
@onready var gpu_particles_2d_2: GPUParticles2D = $"../Graphics/Gun/GPUParticles2D2"
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var hold_timer: Timer = $HoldTimer

var cross_group: Array[Node]
var _cross_damage: DamageData = null
var index: int = 0
var ps_luck: int = 0
var luck_cd: int = 0

var on_charge_up: bool = false
var gun_bullet: PackedScene
var shoot_pressed: bool = false
var value: Array

func _ready():
	super._ready()
	charge_up.timeout.connect(gun_on_charge_up)
	hold_timer.timeout.connect(add_charge_buff)
	gun.can_shoot = false
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	
	if now_t == 1:
		GameEvents.enemy_damage_taken.connect(hit_add_cross_bullet)
		GameEvents.global_time_count.connect(time_count)
	elif now_t == 2:
		buff_layer = 20
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.bullet_damage_mult += 0.25
		PlayerData.update_player_ability()
	elif now_t == 3:
		buff_layer = 30
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.bullet_damage_mult += 0.25
		PlayerData.update_player_ability()

func normal_shoot():
	if gun_bullet != null and gun.bullet != gun_bullet:
		gun.bullet = gun_bullet
		gun.bullet_pool_id = "player_bullet"
	gun.can_shoot = true
	if gun.player != null and gun.is_shoot == true and gun.shoot_timer.time_left <= 0 and gun.ammo_reload_timer.time_left <= 0:
		gun._shoot()

func charge_up_shoot():
	gun.can_shoot = true
	if gun_bullet == null:
		gun_bullet = gun.bullet
	if gun.bullet != sniper_bullet:
		gun.bullet = sniper_bullet
		gun.bullet_pool_id = "player_sniper_bullet"
	if gun.player != null and gun.is_shoot == true and gun.shoot_timer.time_left <= 0 and gun.ammo_reload_timer.time_left <= 0:
		gun._shoot()

func _physics_process(delta: float) -> void:
	if shoot_pressed == true:
		if gun.player != null and gun.is_shoot == true and gun.shoot_timer.time_left <= 0 and gun.ammo_reload_timer.time_left <= 0:
			if charge_up.time_left <= 0 and on_charge_up == false:
				if gun.now_bullet_ammo <= 0:
					gun._ammo_reload()
				else:
					charge_up.start()
					gpu_particles_2d_2.emitting = true
		else:
			if gun.now_bullet_ammo <= 0:
				gun._ammo_reload()

func _unhandled_input(event:InputEvent ) -> void:
	
	if player.player_stop == false:
		if event.is_action_pressed("fire"):
			gun.can_shoot = false
			shoot_pressed = true
		
		if event.is_action_released("fire"):
			charge_up.stop()
			hold_timer.stop()
			audio_stream_player_2d.stop()
			shoot_pressed = false
			gpu_particles_2d.emitting = false
			gpu_particles_2d_2.emitting = false
			if on_charge_up == false:
				normal_shoot()
			else:
				charge_up_shoot()
				on_charge_up = false

func time_count():
	if luck_cd > 0:
		luck_cd -= 1
		if luck_cd <= 0:
			ps_luck = 0

func gun_on_charge_up():
	on_charge_up = true
	gpu_particles_2d.emitting = true
	audio_stream_player_2d.play()
	hold_timer.start()

func add_charge_buff():
	ps_luck += 6
	luck_cd = 10
	player.player_buff_manager.apply_buff(player_buff, value)
	if now_t >= 2:
		player.player_buff_manager.apply_buff(player_buff, value)
	if now_t >= 3:
		player.player_buff_manager.apply_buff(player_buff, value)
		player.player_buff_manager.apply_buff(player_buff, value)

func hit_add_cross_bullet(final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		var luck = randf_range(0, 100)
		if luck < 10 + ps_luck:
			var ins
			var max_value = cross_group.size()
			var enemy_body = get_node_or_null(body_path)
			if enemy_body == null:
				return
			if max_value > 30:
				ins = cross_group[index]
				index = wrapi(index + 1, 0, max_value)
				ins.global_position = enemy_body.global_position
				ins.damage_data = DamageData.fill(ins.damage_data, {
					"damage": damage_data.base_damage,
					"type": GameTags.PS_DAMAGE,
					"source": GameTags.PS_DAMAGE,
					"node": ins,
				})
				ins.call_deferred("active_state")
			else:
				_cross_damage = damage_data
				ins = ProjectileSpawner.spawn_core(
					cross_bullet, "", "BulletRoot", self, Faction.PLAYER_SIDE,
					enemy_body.global_position, 0.0, Vector2.ZERO,
					false, true, true,
					Callable(self, "_configure_cross_bullet")
				)
				_cross_damage = null
				cross_group.push_back(ins)

func _configure_cross_bullet(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": _cross_damage.base_damage,
		"type": GameTags.PS_DAMAGE,
		"source": GameTags.PS_DAMAGE,
		"node": node,
	})


# 联机：同步蓄力发光（供 player.gd 汇总子节点状态）
func get_network_character_state() -> int:
	return 1 if on_charge_up else 0


func apply_network_character_state(state: int) -> void:
	var charging: bool = state == 1
	if gpu_particles_2d != null:
		gpu_particles_2d.emitting = charging
