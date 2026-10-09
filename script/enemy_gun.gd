class_name EnemyGun
extends Node2D

@export var gun_scale: float = 1
@export var stats: EnemyStats
@export var knockback_force: int = 150
@export var bullet_launcher: Node
@export var shoot_flash: PackedScene = preload("res://scenes/enemies/shoot_flash_2.tscn")

@warning_ignore("unused_signal")
signal shoot_end

@onready var timer = get_node_or_null("Timer")
@onready var fire_anim = get_node_or_null("FireAnim")

var _burst_token: int = 0
var firing_stopped: bool = false

func _ready():
	if stats != null and not stats.is_dead.is_connected(stop_firing):
		stats.is_dead.connect(stop_firing)

func begin_burst() -> int:
	firing_stopped = false
	_burst_token += 1
	return _burst_token

func burst_alive(tok: int) -> bool:
	return tok == _burst_token

func stop_firing():
	_burst_token += 1
	firing_stopped = true
	if timer != null:
		timer.stop()
	_stop_extra()

func _stop_extra() -> void:
	pass

func _apply_converted_source():
	var body: Node = stats.get_parent() if stats != null else null
	if body != null and body.get("faction") != null and body.get("faction") == Faction.PLAYER_SIDE:
		bullet_launcher.source_faction = Faction.PLAYER_SIDE
		bullet_launcher.bullet_damage = DamageRouter.converted_damage(body.get("player"), body)
	else:
		bullet_launcher.source_faction = Faction.ENEMY_SIDE

func shoot_bullet():
	if stats != null and stats.hp <= 0:
		return
	SoundManager.play_sfx("GunSounds3")
	fire_anim.play("RESET")
	fire_anim.play("fire_anim")
	
	bullet_launcher.bullet_damage = stats.bullet_damage_mult * bullet_launcher.bullet_damage
	bullet_launcher.knockback_force = knockback_force
	_apply_converted_source()
	
	bullet_launcher.shoot_bullet()
	
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.global_position = bullet_launcher.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()
