extends Node2D
## Hare 头顶电池条：复用 Aris 的 heat_bar 外框，内部 10 格黄绿叠层填充。
## 位置每物理帧跟随玩家 sprite 头顶，跳跃/下落一起移动。

const HEAT_BAR := preload("res://ui/heat_bar.png")
const FRAME_SCALE: float = 1.0
const INNER_W: float = 10.0
const INNER_H: float = 4.0

var player: Node
var _value: float = 100.0
var _max_value: float = 100.0
var _alert_time: float = 0.0


func _ready() -> void:
	if player == null:
		player = get_parent()
	z_index = 20
	queue_redraw()


func update_energy(value: float, max_value: float) -> void:
	_value = clampf(value, 0.0, maxf(0.01, max_value))
	_max_value = maxf(0.01, max_value)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var y_off := -24.0
	var sprite = player.get("sprite_2d")
	if sprite is Node2D:
		y_off = (sprite as Node2D).position.y - 24.0
	position = Vector2(0.0, y_off)
	_alert_time += delta
	queue_redraw()


func _draw() -> void:
	# 外框：Aris 的 heat_bar 旋转 90° 横躺（1×，与 Aris 同尺寸），黄绿调制
	draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2(FRAME_SCALE, FRAME_SCALE))
	draw_texture(HEAT_BAR, -HEAT_BAR.get_size() * 0.5, Color(0.78, 1.0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 内部：单条连续填充（无格子）
	var ratio: float = clampf(_value / _max_value, 0.0, 1.0)
	var x0: float = -INNER_W * 0.5
	draw_rect(Rect2(x0, -INNER_H * 0.5, INNER_W, INNER_H), Color(0.12, 0.22, 0.08, 0.85), true)
	if ratio > 0.0:
		draw_rect(Rect2(x0, -INNER_H * 0.5, INNER_W * ratio, INNER_H), Color(0.78, 1.0, 0.30), true)

	# 低电量：红色闪烁描边
	if _value < _max_value * 0.25:
		var a: float = (sin(_alert_time * 10.0) + 1.0) * 0.5
		draw_rect(
			Rect2(x0 - 2.0, -INNER_H * 0.5 - 1.0, INNER_W + 4.0, INNER_H + 2.0),
			Color(1.0, 0.3, 0.2, 0.25 * a),
			false,
			1.0
		)
