extends Node2D
## Chihiro 近战控制器动画道具（纯视觉，不结算、不施加感电）：
## 从玩家手部朝准星方向短抛、旋转，随后淡出并释放。

@onready var sprite: Sprite2D = $Sprite2D

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _dur: float = 0.25
var _spin: float = 0.0


func play(from: Vector2, dir: Vector2) -> void:
	global_position = from
	_from = from
	var d := dir.normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	_to = from + d * 46.0
	_spin = randf_range(-6.0, 6.0)
	rotation = d.angle()
	var tw := create_tween()
	tw.tween_method(_step, 0.0, 1.0, _dur)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.10)
	tw.tween_callback(queue_free)


func _step(t: float) -> void:
	var p := _from.lerp(_to, t)
	p.y -= sin(t * PI) * 10.0
	global_position = p
	rotation += _spin * 0.016
