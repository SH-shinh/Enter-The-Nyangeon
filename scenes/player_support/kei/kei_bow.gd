extends Sprite2D

@export var player: Node

func _physics_process(_delta: float) -> void:
	if player != null:
		self.position.y = player.sprite_2d.position.y - 3
		self.position.x = -5.5 * player.graphics.scale.x + 0.5
