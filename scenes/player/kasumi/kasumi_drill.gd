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

var body_group: Array[Node]

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
@onready var hit_box = $Area2D2

func _ready() -> void:
	GameEvents.round_end.connect(reset_lv)
	GameEvents.enemy_damage_taken.connect(melee_lv_add)
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_exited)
	reset_lv()

func idle_state():
	is_idle = 1
	if !body_group.is_empty():
		body_group.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	animation_player_2.play("RESET")
	is_critical = false
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	if !body_group.is_empty():
		body_group.clear()
	now_cd = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	
	self.visible = true
	animation_player_2.play("drill_anim")
	drill_sounds.pitch_scale = randf_range(0.8,1.2)
	drill_sounds.play()
	lv_num.scale.x = scale_x
	self.scale = Vector2( scale_x * (1 + now_lv * 0.0015), 1 + now_lv * 0.0015)
	apply_melee_damage_data()

func time_count():
	add_damage_data()
	
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

func melee_lv_add(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.damage_type.has(GameTags.MELEE_DAMAGE) and damage_data.source_type.has(GameTags.EQUIP):
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
	
	if ins.damage_data == null:
		ins.damage_data = DamageData.new()
	else:
		ins.damage_data.reset_data()
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		ins.damage_data.is_crit = true
		ins.damage_data.base_damage = max(1, round(explosion_damage * player.stats.critical_damage))
	else:
		ins.damage_data.is_crit = false
		ins.damage_data.base_damage = max(1, round(explosion_damage))
	
	ins.damage_data.knockback_force = player.stats.bullet_knockback
	ins.damage_data.damage_type.append(GameTags.EXPLOSION_DAMAGE)
	ins.damage_data.source_type.append(GameTags.EQUIP)
	
	ins.explosion_range = player.stats.explosion_range * base_explosion_range * range_mult
	
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	ins.damage_data.source_node = ins.get_path()
	ins.active_state()
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
		damage_mult = 1 + (player.player_buff_manager.current_buff[player_buff.id]["layer"] * 0.4)
		range_mult = 1 + (player.player_buff_manager.current_buff[player_buff.id]["layer"] * 0.05)
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

func apply_melee_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage * player.stats.equip_damage * player.stats.critical_damage))
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage * player.stats.equip_damage))
		hit_box.damage_data.is_crit = false
	
	hit_box.damage_data.knockback_force = min( player.stats.bullet_knockback + 200, 100)
	hit_box.damage_data.damage_type.append(GameTags.MELEE_DAMAGE)
	hit_box.damage_data.damage_type.append(GameTags.EQUIP_DAMAGE)
	hit_box.damage_data.hit_box_center = hit_box.global_position
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(GameTags.EQUIP)
	hit_box.damage_data.flags.append(GameTags.KNOCKBACK_ATTRACT)

func add_damage_data():
	if !body_group.is_empty():
		
		var damage_m:int = hit_box.damage_data.base_damage
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			if now_cd <= 0:
				SoundManager.play_sfx("HurtSounds2")
				freeze_frame()
				apply_melee_damage_data()
				if hit_box.damage_data.is_crit == true:
					lv_count()
			else:
				hit_box.damage_data.base_damage = 0
			i.hit_received.emit(hit_box.damage_data)
			
		if now_cd > 0:
			now_cd -= 1
		else:
			now_cd = melee_cd

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_hit_box_exited(hurtbox: Area2D):
	if hurtbox is HurtBox and body_group.has(hurtbox) and !hurtbox.owner.is_in_group("Summoned"):
		body_group.remove_at(body_group.find(hurtbox))
