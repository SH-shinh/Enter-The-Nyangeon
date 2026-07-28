extends Node2D

@export var gun_scale: float = 1
@export var stats: EnemyStats

signal shoot_end

@onready var bullet_launcher = $Sprite2D/BulletLauncher

func shoot_bullet():
	SoundManager.play_sfx("GunSounds3")
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "scale", Vector2(gun_scale,gun_scale), 0.2).from(Vector2(gun_scale * 0.7, gun_scale * 1.6))
	bullet_launcher.bullet_damage_mult = stats.bullet_damage_mult
	bullet_launcher.shoot_bullet.call_deferred()

func emit_shoot_end():
	shoot_end.emit()

func gun_shot():
	$AnimationPlayer.play("shoot_anim")
