extends Enemy
class_name Automaton

enum State {
	IDLE,
	SHOOTING,
	AIMING,
	RUNNING,
	DEAD,
}

@export var shoot_range: int
@export var back_range: int
@export var aim_and_move: float
@export var shoot_and_move: float
@export_range(0,100) var surround_tendency: int
@export var surround_time: int
@export var sniper: bool = false

var can_shoot: bool = false

var aim_end: bool = false

var distance : float = 0

var dir_v: Vector2 = Vector2.ZERO

var aim_and_move_speed: int
var shoot_and_move_speed: int

var move_mod:int = 0

var dir_num: int = 0

@export var shoot_cd_time: int = 40
@export var aim_time: int = 20

var decision_time: int = 5

@onready var shoot_cd: int = shoot_cd_time
var aim: int = 0

@onready var buff_box = $%BuffBox
@onready var gun = $Graphics/Gun

func active_state():
	super.active_state()
	can_shoot = false
	aim_end = false
	move_mod = 0

func time_count():
	super.time_count()
	
	if aim > 0:
		aim -= 1
		if aim <= 0:
			can_shoot = true
	
	if shoot_cd > 0:
		shoot_cd -= 1
	
	if decision_time > 0:
		decision_time -= 1
		if decision_time <= 0:
			if is_standby():
				dir_v = Vector2.ZERO
				move_mod = 0
			else:
				dir_v = get_distance_to_player()
			shoot_and_move_speed = int(shoot_and_move * stats.MAX_SPEED)
			decision_time = 5

func tick_physics(state: State, delta: float) -> void:
	if is_idle == 1:
		return
	
	ACCELERATION = stats.move_acceleration()
	
	apply_soft_collision()
	
	if player != null and not is_standby():
		var target := get_target()
		if target != null and (aim_end == false or sniper == true):
			gun.look_at(target.global_position + Vector2(0, -8))
	
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		
		State.SHOOTING:
			shoot_bullet()
			move(delta, ACCELERATION, shoot_and_move_speed)
		
		State.AIMING:
			move(delta, ACCELERATION, aim_and_move_speed)
		
		State.RUNNING:
			move(delta, ACCELERATION, stats.MAX_SPEED)

func face_to_player():
	var t := get_target()
	if t != null and self.position.distance_to(t.global_position) > 5:
		if aim_end == false or sniper == true:
			return (t.global_position - global_position).normalized()
	return Vector2.ZERO

func get_distance_to_player():
	var tp := get_target_position()
	distance = self.position.distance_to(tp)
	if distance > shoot_range:
		move_mod = 0
		return (tp - global_position).normalized()
	elif distance < back_range:
		move_mod = 0
		return (global_position - tp).normalized()
	else:
		move_mod = 2
		var n := (tp - global_position).normalized()
		if dir_num == 0:
			return Vector2(n.y, -n.x)
		else:
			return Vector2(-n.y, n.x)

func shoot_bullet():
	if is_standby():
		return
	if shoot_cd <= 0 and can_shoot == true:
		aim_end = true
		gun.gun_shot()
		shoot_cd = shoot_cd_time
		can_shoot = false

func move(delta: float, acceleration_local: float ,MAX_SPEED: float ) -> void:
	
	direction = dir_v
	var look_dir = face_to_player()
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, acceleration_local * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, acceleration_local * delta)
		
		if look_dir.x > 0:
			graphics.scale.x = 1
		elif look_dir.x < 0:
			graphics.scale.x = -1
	
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

func get_next_state(state: State) -> State:
	
	var is_still := velocity.x == 0 and velocity.y == 0
	if stats.hp == 0 :
		return State.IDLE
	
	match state:
		
		State.IDLE:
			if move_mod == 2:
				return State.AIMING
			if not is_still:
				return State.RUNNING
		
		State.SHOOTING:
			if can_shoot == false and aim_end == false:
				if move_mod == 0:
					return State.RUNNING
				return State.IDLE
			
		State.AIMING:
			if move_mod == 0:
				return State.RUNNING
			if can_shoot == true and aim <= 0:
				return State.SHOOTING
			
		State.RUNNING:
			if move_mod == 2:
				return State.AIMING
			if is_still:
				return State.IDLE
			
	return state
	
func transition_state(_from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			#move_mod = 1
			sprite_2d.play("idle")
		
		State.SHOOTING:
			if shoot_and_move_speed == 0:
				sprite_2d.play("idle")
			else: 
				sprite_2d.play("run")
		
		State.AIMING:
			dir_num = randi_range(0,1)
			rand_aim_and_move_speed()
			surround_player()
			aim = aim_time
			if aim_and_move_speed == 0:
				sprite_2d.play("idle")
			else: 
				sprite_2d.play("run")
		
		State.RUNNING:
			#move_mod =0
			can_shoot = false
			sprite_2d.play("run")
		
		State.DEAD:
			pass

func rand_aim_and_move_speed():
	var num:float = randf_range(0,aim_and_move)
	if num < 0.3 :
		num = 0
	aim_and_move_speed = int(num * stats.MAX_SPEED)

func surround_player():
	var num = randf_range(0,100)
	if num < surround_tendency:
		aim = surround_time
		aim_and_move_speed = stats.MAX_SPEED

func _on_gun_shoot_end():
	aim_end = false
