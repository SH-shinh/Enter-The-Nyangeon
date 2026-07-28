extends Node2D

@export var stats: Stats
@export var summoned_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@export var enemy_buff: Buff
@export var buff_layer_2: int
@export var buff_value_2: float
@export var buff_erase_timer_2: float

@onready var turret = preload("res://scenes/update_item/utaha_turret_body.tscn")
@onready var progress_bar = $ProgressBar
@onready var animation_player = $AnimationPlayer
@onready var lv_num = $LVNum
@onready var timer = $Timer
@onready var collision_shape_2d = $Node2D/Area2D/CollisionShape2D

@onready var ring_anim = $Node2D/AnimationPlayer
@onready var gpu_particles_2d = $Node2D/GPUParticles2D


var spawn_point: Vector2 = Vector2(704, 448)

var value: Array
var value_2: Array
var now_t:int

var up_v: int = 6

func _ready():
	PlayerData.set_player.connect(add_turret_mk_3)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		add_turret()
		up_v = 12
	elif now_t == 2:
		value = [buff_layer, buff_value, buff_erase_timer]
		gpu_particles_2d.emitting = true
		collision_shape_2d.disabled = false
		ring_anim.play("new_animation")
		add_turret()
	elif now_t == 3:
		value_2 = [buff_layer_2, buff_value_2, buff_erase_timer_2]
		GameEvents.enemy_body.connect(add_mark_buff)
		GameEvents.summoned_bullet_hit_enemy.connect(add_damage)

func show_progress(max_v: int, value: int, lv: int):
	progress_bar.visible = true
	lv_num.visible = true
	lv_num.text = str("LV " + str(lv))
	if value == max_v:
		animation_player.play("level_up_anim")
	progress_bar.max_value = max_v
	progress_bar.value = value
	timer.start()

func add_turret():
	var turret_position = spawn_point + Vector2( randf_range(-80,80), randf_range(-50,50)  )
	var ins = turret.instantiate()
	ins.global_position = turret_position
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)

func add_turret_mk_3():
	var turret_position = spawn_point + Vector2( randf_range(-80,80), randf_range(-50,50)  )
	var ins = turret.instantiate()
	ins.global_position = turret_position
	ins.scale = Vector2(1, 1)
	ins.stats.summoned_damage = 25
	ins.stats.summoned_shoot_time = 350
	ins.stats.summoned_max_ammo = 100
	ins.summoned_ammo = 100
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	

func add_mark_buff(enemy_body: Node, bullet_body: Node):
	if bullet_body.get("is_player_shoot") == true:
		enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value_2)

func add_damage(bullet_body: Node, enemy_body: Node):
	if enemy_body.enemy_buff_manager.current_buff.has(enemy_buff.id):
		enemy_body.hurt_damage = bullet_body.bullet_damage * enemy_body.enemy_buff_manager.current_buff[enemy_buff.id]["layer"] * 0.15
		enemy_body.emit_signal("is_hurt")

func _on_timer_timeout():
	progress_bar.visible = false
	lv_num.visible = false


func _on_area_2d_body_entered(body):
	if body.is_in_group("Summoned"):
		body.summoned_buff_manager.apply_buff(summoned_buff, value)

func _on_area_2d_body_exited(body):
	if body.is_in_group("Summoned"):
		body.summoned_buff_manager.remove_buff(summoned_buff)
