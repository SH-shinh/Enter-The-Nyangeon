extends Node2D

@export var pool_id: String = "bullet_smoke_2"

@onready var animation_player = $AnimationPlayer

var is_idle: int = 0

func _ready():
	PoolManager.add_pool(pool_id,self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	smoke_reset()

func active_state():
	is_idle = 0
	self.visible = true

func smoke_reset():
	animation_player.play("RESET")

func smoke_anim():
	active_state()
	animation_player.play("new_animation")

func remove_pool():
	FloatingPool.remove_se_2_pool(self)
