class_name EnemySpreadBullet
extends EnemyBullet

@export var shrapnel_scale: float = 0.6
@export var shrapnel_random_speed: bool = false
@export var shrapnel_speed: int = 100
@export var shrapnel_speed_min: int = 50
@export var shrapnel_speed_max: int = 150

var firest_speed: int = 0

@onready var bullet_launcher = $BulletLauncher

func bullet_kill():
	if now_penetrate <= 0:
		bullet_shoot()
		bulletSmoke(global_position)
		idle_state.call_deferred()

func bullet_shoot():
	bullet_launcher.source_faction = source_faction
	if damage_data != null:
		bullet_launcher.bullet_damage = damage_data.base_damage
	
	bullet_launcher.bullet_penetrate = penetrate
	bullet_launcher.collision_num = collision_num
	bullet_launcher.kill_time = 110
	bullet_launcher.bullet_scale = shrapnel_scale
	
	for i in shoot_bullet_num:
		bullet_launcher.rotation = randf_range(-PI,PI)
		if shrapnel_random_speed:
			bullet_launcher.bullet_speed = randf_range(shrapnel_speed_min, shrapnel_speed_max)
		else:
			bullet_launcher.bullet_speed = shrapnel_speed
		bullet_launcher.shoot_bullet()

func _on_bullet_kill_timer_timeout():
	
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		bullet_shoot()
		bulletSmoke(global_position)
		idle_state.call_deferred()
