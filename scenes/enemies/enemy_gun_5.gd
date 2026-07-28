extends Node2D

@export var gun_scale: float = 1
@export var stats: EnemyStats

signal shoot_end

@onready var bullet_launcher = $BulletLauncher2
@onready var shoot_flash = preload("res://scenes/enemies/shoot_flash_2.tscn")
@onready var marker_2d = $Sprite2D/Marker2D
@onready var timer = $Timer


func _ready():
	stats.is_dead.connect(bullet_launcher.emit_can_move)

func shoot_bullet():
	
	bullet_launcher.bullet_damage_mult = stats.bullet_damage_mult
	bullet_launcher.shoot_bullet.call_deferred()
	for i in 12:
		var tween = get_tree().create_tween().set_parallel(true)
		tween.tween_property($Sprite2D, "scale", Vector2(gun_scale,gun_scale), 0.2).from(Vector2(gun_scale * 0.7, gun_scale * 1.6))
		
		var now_shoot_flash = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = bullet_launcher.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()
		timer.start()
		await timer.timeout

func gun_shot():
	shoot_bullet()
	await bullet_launcher.can_move
	shoot_end.emit()
