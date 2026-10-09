class_name KeiSummoned
extends SummonedFollower

# 彩蛋：aris_armed 起飞（仅 JUMP 阶段）时，近距离内的 kei 会被带着一起飞行。
# 实体位于 aris_armed 实体下方 carry_body_offset，精灵视觉位于 aris 精灵下方 carry_sprite_gap，
# 并进入 JUMP 状态；携带期间把实际位移写入 velocity 供头发飘动，落地后松开，恢复普通跟随。

@export var carry_enabled: bool = true
@export var carry_trigger_distance: float = 90.0
@export var carry_body_offset: Vector2 = Vector2(0.0, 5.0)   # kei 实体相对 aris 实体
@export var carry_sprite_gap: float = 20.0                   # kei 精灵相对 aris 精灵的下方距离
@export var carry_follow_speed: float = 30.0                 # 每帧插值系数 = k*delta（60Hz 下 0.5），滞后 ≈ v/k

var is_carried: bool = false
var _saved_can_move: bool = true
var _saved_sprite_y: float = -17.0

func tick_physics(state: int, delta: float) -> void:
	_update_carry()
	if is_carried:
		sprite_2d.position.y = player.sprite_2d.position.y + (carry_sprite_gap - carry_body_offset.y)
	super.tick_physics(state, delta)
	if is_carried:
		var prev := global_position
		global_position = _carry_target(delta)
		if delta > 0.000001:
			velocity = (global_position - prev) / delta

func get_next_state(state: int) -> int:
	if is_carried:
		return State.JUMP
	return super.get_next_state(state)

func transition_state(from: int, to: int) -> void:
	if is_carried and to == State.JUMP:
		z_index = 3
		sprite_2d.play("jump")
		smoke.emitting = false
		return
	super.transition_state(from, to)

func follow_player_jump(position: Vector2) -> void:
	if is_carried:
		return
	super.follow_player_jump(position)

func _update_carry() -> void:
	if not carry_enabled or is_idle == 1 or not is_instance_valid(player) or not _is_aris():
		if is_carried:
			_release()
		return
	if is_carried:
		if _player_on_floor():
			_release()
		return
	# 仅在 aris 的 JUMP（起飞）状态且范围内才携带
	if _player_in_takeoff() and global_position.distance_to(player.global_position) <= carry_trigger_distance:
		_attach()

func _is_aris() -> bool:
	return player.get("is_hovering") != null

func _player_in_takeoff() -> bool:
	var jump_timer = player.get("jump_timer")
	return jump_timer != null and jump_timer.time_left > 0.0  # JUMP（起飞）期间 jump_timer 在跑

func _player_on_floor() -> bool:
	var spr: Node2D = player.get("sprite_2d")
	return spr == null or spr.position.y == -17.0

func _attach() -> void:
	is_carried = true
	_saved_can_move = can_move
	_saved_sprite_y = sprite_2d.position.y
	can_move = false
	velocity = Vector2.ZERO
	jump_dely.stop()
	is_jump_request = false

func _release() -> void:
	is_carried = false
	can_move = _saved_can_move
	sprite_2d.position.y = _saved_sprite_y
	velocity = Vector2.ZERO
	jump_dely.stop()
	is_jump_request = false

func _carry_target(delta: float) -> Vector2:
	var target: Vector2 = player.global_position + carry_body_offset
	if carry_follow_speed > 0.0:
		return global_position.lerp(target, clampf(carry_follow_speed * delta, 0.0, 1.0))
	return target
