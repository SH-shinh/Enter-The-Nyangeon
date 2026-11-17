extends Node2D

## Kotama 破隐首枪的枪口爆发：一次性播放后自毁。
## 帧图以 ORIGIN 为枪口原点，节点 rotation 由 KotamaPS 按子弹方向设置。

const FRAMES: SpriteFrames = preload("res://scenes/effects/kotama_break_muzzle_frames.res")
const ORIGIN := Vector2(24, 48)

@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.offset = -ORIGIN
	_sprite.animation_finished.connect(queue_free)
	_sprite.play("default")
