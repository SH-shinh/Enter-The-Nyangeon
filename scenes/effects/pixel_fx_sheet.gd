extends Node2D

## 播放烘焙好的 pixelfx `heal-aoe`（圆形、无光柱、金色）环动画。
## 两个播放器错相：第二个环在第一个完全消失前滚出（图集 2.0s、相位差 1.0s）。
## 为什么不跑 LIVE：实测 update+draw 约 58ms/帧；烘焙后运行时零 CPU。
## 重新烘焙：godot --headless --path . -s res://script/bake_pixelfx_fx.gd

const FRAMES := preload("res://scenes/effects/heal_ring_frames.res")
## 与 pixelfx_heal_ring.gd 的 meta.origin 对应
const RING_ORIGIN := Vector2(104, 104)

## 第二个环相对第一个的起始延迟（秒），取图集时长的一半 → 环每 1.0s 一个、恒有 2 环交叠。
@export var phase_offset := 1.0

@onready var _a: AnimatedSprite2D = $SpriteA
@onready var _b: AnimatedSprite2D = $SpriteB


func _ready() -> void:
	for s in [_a, _b]:
		s.sprite_frames = FRAMES
		s.centered = false
		s.offset = -RING_ORIGIN
	_a.play("default")
	if phase_offset > 0.0:
		_start_second()
	else:
		_b.play("default")


func _start_second() -> void:
	await get_tree().create_timer(phase_offset).timeout
	if is_instance_valid(self):
		_b.play("default")


## 回血时让 A 重新滚一次（B 保持原相位，避免突然同相）。
func play() -> void:
	if _a != null:
		_a.play("default")
