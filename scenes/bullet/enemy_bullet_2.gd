class_name EnemySpreadBullet
extends EnemyBullet

@export var shrapnel_scale: float = 0.6
@export var shrapnel_random_speed: bool = false
@export var shrapnel_speed: int = 100
@export var shrapnel_speed_min: int = 50
@export var shrapnel_speed_max: int = 150

var firest_speed: int = 0

# 已提交清场的生命周期代数：同一次激活内（含同帧多次清场）只分裂/冒烟一次。
var _clear_gen: int = -1

@onready var bullet_launcher = $BulletLauncher

func bullet_clear():
	# 待机弹不分裂、不冒烟；重复清场（穿透/撞墙/round_end 同帧叠加）只生效一次。
	if is_idle == 1:
		return
	var gen := _life_gen
	if _clear_gen == gen:
		return
	_clear_gen = gen
	bullet_shoot()
	bulletSmoke(global_position)
	# 延迟回池仍保留（避免在物理/信号回调里直接改形状），但带代数校验：
	# 旧的延迟回调不会把已经复用并重新激活的对象打回待机。
	call_deferred("_idle_if_generation", gen)

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
		bullet_clear()
