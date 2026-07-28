extends Node2D

@export var body: Node
@export var timer: int = 10

@onready var fire_field: PackedScene = preload("res://scenes/enemies/enemy_fire_field.tscn")

var now_time: int

func _ready() -> void:
	now_time = timer
	GameEvents.global_time_count.connect(time_count)
	body.stats.is_dead.connect(reset_timer)

func reset_timer():
	now_time = timer

func time_count():
	if body.is_idle == 1:
		return
	
	if now_time > 0:
		now_time -= 1
		if now_time <= 0:
			now_time = timer
			var fire_ins = PoolManager.get_pool("enemy_fire_field")
			if fire_ins == null or fire_ins.is_idle == 0:
				fire_ins = fire_field.instantiate()
				get_tree().get_first_node_in_group("SELayer").add_child(fire_ins)
			fire_ins.global_position = self.global_position
			fire_ins.active_state()
