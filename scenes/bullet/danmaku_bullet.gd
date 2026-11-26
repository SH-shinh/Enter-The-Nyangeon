class_name DanmakuBullet
extends EnemyBullet

## 弹幕专用弹体：在 EnemyBullet 的直线飞行基础上增加「弧线 / 追踪 / 加速」。
## 只重写移动；激活/回池/撞墙/寿命/伤害全部沿用 EnemyBullet。
## 约定：direction 恒为单位向量（见 docs/SYSTEMS.md §2.1b 的数值安全约束）。

## 当前飞行速度（像素/秒）；active_state 时从 EnemyBullet.speed 同步。
var move_speed: float = 100.0
## 沿飞行方向加速度（像素/秒²）。
var move_accel: float = 0.0
## 弹道自旋（度/秒）。
var curvature_deg_per_sec: float = 0.0
## 追踪转向率（度/秒）。
var homing_deg_per_sec: float = 0.0
## 追踪有效时长（秒）。
var homing_duration: float = 0.0
## 追踪目标（发射器写入；为空时回退到 "Player" 组）。
var homing_target: Node2D = null

var _homing_left: float = 0.0


func active_state() -> void:
	super.active_state()
	move_speed = maxf(1.0, float(speed))
	_homing_left = maxf(0.0, homing_duration)
	if homing_target != null and not is_instance_valid(homing_target):
		homing_target = null


func idle_state() -> void:
	super.idle_state()
	move_speed = 0.0
	_homing_left = 0.0
	homing_target = null


func set_homing_target(target: Node2D) -> void:
	homing_target = target


func _physics_process(delta: float) -> void:
	if is_idle == 1 or is_stop:
		return

	if homing_deg_per_sec != 0.0 and _homing_left > 0.0:
		var target := _resolve_homing_target()
		if target != null:
			var to_target := target.global_position - global_position
			if to_target.length_squared() > 0.0001:
				direction = DanmakuMath.turn_toward(
					direction, to_target.normalized(), homing_deg_per_sec * delta
				)
		_homing_left -= delta

	if curvature_deg_per_sec != 0.0:
		direction = DanmakuMath.curve_direction(direction, curvature_deg_per_sec, delta)

	if move_accel != 0.0:
		move_speed = maxf(1.0, move_speed + move_accel * delta)

	if is_decay:
		move_speed = move_toward(move_speed, 0.0, maxf(0.0, ACCELERATION) * delta)

	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	global_position += direction * move_speed * delta


func _resolve_homing_target() -> Node2D:
	if homing_target != null and is_instance_valid(homing_target):
		return homing_target
	homing_target = null
	if not is_inside_tree():
		return null
	var candidate := get_tree().get_first_node_in_group("Player")
	if candidate is Node2D:
		homing_target = candidate as Node2D
	return homing_target
