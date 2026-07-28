extends Node2D

@onready var timer = $Timer


var bullet: Node
var value: Array

func _ready():
	bullet = get_parent()
	bullet.in_idle.connect(clear_self)
	timer.timeout.connect(bullet_damage_add)

func bullet_damage_add():
	bullet.bullet_damage *= 1.2

func clear_self(_bullet_body: Node):
	queue_free.call_deferred()
