extends Node2D

var explosion_range: float = 9
var knockback: int = 0
var bullet_damage: int = 0
var shoot_bullet_num: int = 12
var bullet_damage_mult: float = 1

var is_idle: int = 1

@onready var explosion:PackedScene = preload("res://scenes/bullet/enemy_explosion_damage.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var bullet_launcher: Node2D = $TextureRect/BulletLauncher

@export var bullet_id: String

func _ready():
	PoolManager.add_pool(bullet_id,self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")

func shoot_bullet():
	if bullet_launcher.bullet_count > 0:
		bullet_launcher.bullet_damage_mult = bullet_damage_mult
		bullet_launcher.shoot_bullet_num = shoot_bullet_num
		bullet_launcher.shoot_bullet()

func add_explosion():
	
	var ins = PoolManager.get_pool("enemy_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion.instantiate()
		add_ins = true
	
	ins.global_position = global_position
	ins.explosion_damage = bullet_damage
	ins.explosion_knockback = 2 * knockback
	ins.explosion_range = explosion_range
	
	SoundManager.play_sfx("ExplosionSounds3")
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.is_explosion()
