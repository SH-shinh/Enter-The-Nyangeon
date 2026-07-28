extends Node2D

@export var gun: Node
@onready var ex_bullet = preload("res://scenes/bullet/momoi_ex_bullet.tscn")
@onready var shoot_flash = preload("res://scenes/weapon/Unique_Idea/shoot_flash.tscn")
@onready var ex_skill_shoot_timer = $EXSkillShootTimer
@onready var ex_skill_timer = $EXSkillTimer
@onready var ex_skill_timer_bar = $CanvasLayer/EXSkillTimerBar

var stats
var player

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	stats = player.stats

func _process(delta):
	ex_skill_shoot_timer.wait_time = float(60.0 / (stats.bullet_shoot_time * 1.5) )
	ex_skill_timer_bar.value = ex_skill_timer.time_left / ex_skill_timer.wait_time

func _ex_skill_shoot():
	gun.ammo_reload_timer.wait_time = stats.reload_timer
	
	if gun.now_bullet_ammo <= 0:
		gun._ammo_reload()
		return
	gun.fire_sounds.play()
	gun.now_bullet_ammo -= stats.bullet_cost / 2.0
	
	var direction: Vector2 = global_position \
			.direction_to(get_global_mouse_position()) \
			.normalized()
	
	ex_skill_shoot_timer.start()
	
	for i in randi_range(10 + stats.bullet_count - 2, 10 + stats.bullet_count + 1):
		var now_shoot_flash = shoot_flash.instantiate()
		var now_bullet = ex_bullet.instantiate()
		now_bullet.speed = randi_range(stats.bullet_speed * 1.1, stats.bullet_speed * 1.6)
		now_bullet.penetrate = stats.bullet_penetrate
		now_bullet.collision_num = stats.collision_num
		now_bullet.position = gun.shoot_position.global_position
		now_bullet.is_player_shoot = true
		
		var arc_rad = deg_to_rad(randf_range(60 * 0.8, 60 * 1.3 ))
		var increment = arc_rad / (10 + stats.bullet_count - 1)
		now_bullet.global_rotation = (
			global_rotation +
			increment * i -
			arc_rad / 2
		)
		
		var player = get_tree().get_first_node_in_group("Player")
		var recoil_direction : Vector2 = global_position \
				.direction_to(get_global_mouse_position()) \
				.normalized()
		var recoil_speed = recoil_direction * ( stats.bullet_recoil / 7 + stats.bullet_count )
	
		player.velocity -= recoil_speed
		
		now_shoot_flash.position = gun.shoot_position.global_position
		now_shoot_flash.rotation = direction.angle()
		gun.call_deferred("_shootAnim")
		get_tree().get_first_node_in_group("BulletRoot").add_child(now_shoot_flash)
		get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		GameEvents.emit_player_shot_position(gun.shoot_position.global_position,now_bullet)


func _on_ex_skill_timer_timeout():
	gun.can_ex_skill = false
	gun.can_shoot = true
