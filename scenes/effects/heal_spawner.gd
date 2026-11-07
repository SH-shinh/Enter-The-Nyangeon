extends "res://scenes/effects/pooled_sprite_spawner.gd"

## 回血光点螺旋：每次回血 spawn() 一个，**挂在玩家节点下**（跟随玩家），播完归还对象池。

const FRAMES := preload("res://scenes/effects/serina_heal_frames.res")


func _ready() -> void:
	frames = FRAMES
	origin = Vector2(24, 64)
	sprite_scale = 1.6
	pool_cap = 3
	attach_to_target = true
	sprite_z = 0
	super()
