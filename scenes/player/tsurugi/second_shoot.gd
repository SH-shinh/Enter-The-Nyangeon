extends Node2D
@export var player: Node
@export var second_gun: Node

func kick_start():
	second_gun.is_shoot = true

func _unhandled_input(event:InputEvent ) -> void:
	if event.is_action_released("kick"):
		second_gun.is_shoot = false
	
	if event.is_action_pressed("reload"):
		second_gun._ammo_reload()

func _physics_process(delta):
	if player.graphics.scale.x > 0:
		scale.y = 1
	else:
		scale.y = -1
	
	self.position.y = player.sprite_2d.position.y + 12
