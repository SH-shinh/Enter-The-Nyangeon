extends Node2D


var player: Node
@export var player_buff: Buff

var kick_damage: int
var bullet_knockback: int
var player_position: Vector2
var is_critical: bool = false

var melee_cd: int = 2
var now_cd: int = 0

var player_explosion_damage: int = 15
var damage_mult: float = 1
var range_mult: float = 1
var explosion_damage: int = 0

var now_lv: int = 0
var scale_x: float = 1

var damage_count: float = 0

@export var base_explosion_range: int = 5

var enemy_group: Array[Node]

var explosion_num: int = 0
var max_layer: int = 3

var is_idle: int = 1

var freeze_time: int = 0
var freeze_cd: int = 0
var now_t: int = 0

var quip_damage: int = 0

@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var drill_sounds: AudioStreamPlayer2D = $DrillSounds
@onready var explosion_pak: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var lv_num: Label = $LVNum

func _ready() -> void:
	GameEvents.round_end.connect(reset_lv)
	GameEvents.player_melee_hit_enemy.connect(melee_lv_add)
	reset_lv()

func idle_state():
	is_idle = 1
	if !enemy_group.is_empty():
		enemy_group.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	animation_player_2.play("RESET")
	is_critical = false
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	if !enemy_group.is_empty():
		enemy_group.clear()
	now_cd = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	
	self.visible = true
	animation_player_2.play("drill_anim")
	drill_sounds.pitch_scale = randf_range(0.8,1.2)
	drill_sounds.play()
	lv_num.scale.x = scale_x
	self.scale = Vector2( scale_x * (1 + now_lv * 0.0015), 1 + now_lv * 0.0015)

func time_count():
	add_damage()
	
	if freeze_cd > 0:
		freeze_cd -= 1
	
	if freeze_time > 0:
		freeze_time -= 1
		if freeze_time <= 0:
			freeze_frame_reset()

func reset_lv():
	now_lv = 0
	lv_num.text = str(now_lv) + "%"
	self.scale = Vector2(1, 1)
	PlayerData.critical_damage_add -= damage_count
	damage_count = 0

func melee_lv_add(_body: Node):
	lv_count()

func lv_count():
	if now_t > 0:
		now_lv += 1
		lv_num.text = str(now_lv) + "%"
		lv_num.scale.x = scale_x
		self.scale = Vector2( scale_x * (1 + now_lv * 0.0015), 1 + now_lv * 0.0015)
		damage_count += 0.01
		PlayerData.critical_damage_add += 0.01
		PlayerData.update_player_ability()
		
		explosion_num += 1
		if explosion_num > 100:
			explosion_num = 0
			if is_idle == 0:
				add_full_explosion()
	

func add_explosion_ins():
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion_pak.instantiate()
		add_ins = true
	
	ins.global_position = self.global_position
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		ins.explosion_damage = explosion_damage * player.stats.critical_damage
		ins.is_critical = true
	else:
		ins.explosion_damage = explosion_damage
	ins.explosion_knockback = bullet_knockback
	ins.explosion_range = player.stats.explosion_range * base_explosion_range * range_mult
	ins.is_equip_shoot = true
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	ins.is_small_explosion()
	
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()

func add_full_explosion():
	damage_mult = 1 + (max_layer * 0.4)
	range_mult = 1 + (max_layer * 0.05)
	explosion_damage = player_explosion_damage * damage_mult * player.stats.explosion_damage * player.stats.global_damage  * player.stats.equip_damage
	
	add_explosion_ins()

func add_explosion():
	if player.player_buff_manager.current_buff.has(player_buff.id):
		damage_mult = 1 + (player.player_buff_manager.current_buff[player_buff.id]["quantity"] * 0.4)
		range_mult = 1 + (player.player_buff_manager.current_buff[player_buff.id]["quantity"] * 0.05)
		explosion_damage = player_explosion_damage * damage_mult * player.stats.explosion_damage * player.stats.global_damage  * player.stats.equip_damage
		
		add_explosion_ins()
		
		player.player_buff_manager.remove_buff(player_buff)

func particles_shoot():
	gpu_particles_2d_2.emitting = true
	gpu_particles_2d_2.restart()

func freeze_frame():
	if freeze_cd <= 0:
		freeze_cd = 5
		freeze_time = 4
		animation_player_2.speed_scale = 0

func freeze_frame_reset():
	animation_player_2.speed_scale = 1

func add_damage():
	if !enemy_group.is_empty():
		for i in enemy_group.size():
			if now_cd <= 0:
				freeze_frame()
				SoundManager.play_sfx("HurtSounds2")
				enemy_group[i].hurt_damage = kick_damage
				if is_critical == true:
					enemy_group[i].is_critical_hit = true
					GameEvents.emit_player_melee_critical_hit_enemy(enemy_group[i])
					lv_count()
				GameEvents.emit_player_melee_hit_enemy(enemy_group[i])
				GameEvents.emit_equip_hit_enemy(enemy_group[i], self)
			else:
				enemy_group[i].hurt_damage = 0
			var hit_direction = (self.global_position - enemy_group[i].global_position).normalized()
			enemy_group[i].hurt_knockback = min( bullet_knockback + 200 , 100 )
			enemy_group[i].hurt_direction = hit_direction
			enemy_group[i].emit_signal("is_hurt")
			if enemy_group[i].stats.hp <=0:
				GameEvents.emit_equip_kill_enemy()
		if now_cd > 0:
			now_cd -= 1
		else:
			now_cd = melee_cd

func _on_area_2d_2_body_entered(body: Node2D) -> void:
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		
		enemy_group.push_back(body)
	
	if body.is_in_group("Summoned"):
		
		var hit_direction = (body.position - player_position).normalized()
		body.hurt_knockback = min( bullet_knockback + 100, 1000 )
		body.hurt_dir = hit_direction
		
		body.stats.emit_signal("is_hurt")
		SoundManager.play_sfx("HurtSounds2")

func _on_area_2d_2_body_exited(body: Node2D) -> void:
	if body.is_in_group("Enemy") and enemy_group.has(body):
		enemy_group.remove_at(enemy_group.find(body))
