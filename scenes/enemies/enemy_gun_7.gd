extends Node2D

@export var gun_scale: float = 1
@export var stats: EnemyStats
@export var type: Array[String]

signal shoot_end

@onready var formation_launcher: FormationController = $Sprite2D/FormationLauncher
@onready var shoot_flash = preload("res://scenes/enemies/shoot_flash_2.tscn")
@onready var timer = $Timer

var index: int = randi_range(0, 2)

func shoot_bullet():
	SoundManager.play_sfx("GunSounds5")
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "scale", Vector2(gun_scale,gun_scale), 0.2).from(Vector2(gun_scale * 0.7, gun_scale * 1.6))
	formation_launcher.bullet_damage_mult = stats.bullet_damage_mult
	formation_launcher.shoot_bullet.call_deferred()
	
	var now_shoot_flash = PoolManager.get_pool("enemy_flash_1")
	if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
		now_shoot_flash = shoot_flash.instantiate()
		get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
	now_shoot_flash.position = formation_launcher.global_position
	now_shoot_flash.rotation = global_rotation
	now_shoot_flash.active_state()


func gun_shot():
	if formation_launcher.is_active == true:
		shoot_end.emit()
		return
	index = wrapi( index + 1, 0, 3)
	formation_launcher.formation_type = type[index]
	shoot_bullet()
	shoot_end.emit()
