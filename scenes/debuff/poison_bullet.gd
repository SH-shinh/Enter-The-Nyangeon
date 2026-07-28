extends Node2D

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var bullet: Node
var value: Array

func _ready():
	bullet = get_parent()
	bullet.enemy_body_get.connect(add_poison)
	bullet.in_idle.connect(clear_self)

func add_poison(body: Node):
	body.is_poison_hit = true
	buff_value = bullet.bullet_damage
	value = [buff_layer, buff_value, buff_erase_timer]
	body.enemy_buff_manager.apply_buff(enemy_buff, value)

func clear_self(_bullet_body: Node):
	queue_free.call_deferred()
