class_name PropWallBody
extends StaticBody2D

## 障碍碰撞体：层 9(wall) 阻挡角色移动；block_bullets 时层 2 阻挡子弹并加入 BulletWall 组。

@export var block_bullets: bool = true

func _ready() -> void:
	var layer := 256 # wall
	if block_bullets:
		layer |= 2 # bullet_wall
		add_to_group("BulletWall")
	collision_layer = layer
	collision_mask = 0
