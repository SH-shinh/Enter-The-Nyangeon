extends Node2D

@export var stats: EnemyStats
@onready var bullet_launcher = $BulletLauncher

var body: Node

func _ready():
	body = get_parent()
	body.stats.is_dead.connect(is_dead_shoot)

func is_dead_shoot():
	bullet_launcher.bullet_damage_mult = stats.Enemy_bullet_damage
	bullet_launcher.shoot_bullet.call_deferred()
