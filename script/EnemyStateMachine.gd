class_name EnemyStateMachine
extends Node

var cd_time: int = 0

var current_state: int = -1:
	set(v):
		owner.transition_state(current_state, v)
		current_state = v
		
		
func _ready() -> void:
	await owner.ready
	current_state = 0
	GameEvents.global_time_count.connect(time_count)

func time_count():
	if cd_time > 0:
		cd_time -= 1

func _physics_process(delta: float) -> void:
	if owner.get("frozen") == true:
		owner.velocity = Vector2.ZERO
		return
	# 眩晕（stun buff）：不推进状态机 → 同时停移动与 tick_physics 内的射击。
	if owner.has_method("is_stunned") and owner.is_stunned():
		owner.velocity = Vector2.ZERO
		return
	if cd_time <= 0:
		cd_time = 3
		while  true:
			var next := owner.get_next_state(current_state) as int
			if current_state == next:
				break
			current_state = next
		
	owner.tick_physics(current_state, delta)
