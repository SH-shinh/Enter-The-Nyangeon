extends Enemy
class_name EliteAutomaton

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

var can_shoot: bool = false

var aim_end: bool = false

var distance : float = 0

var dir_v: Vector2 = Vector2.ZERO

var aim_and_move_speed: int
var shoot_and_move_speed: int

var move_mod:int = 0

var dir_num: int = 0

var head_look: float

@export var shoot_cd_time: int = 40
@export var aim_time: int = 20

var decision_time: int = 5

@onready var shoot_cd: int = shoot_cd_time
var aim: int = 0

@onready var buff_box = $%BuffBox
@onready var gun = $Graphics/Gun
@onready var bullet_launcher = $Graphics/Gun/Sprite2D/BulletLauncher
@onready var head = $Graphics/AnimatedSprite2D2

func active_state():
	super.active_state()
	can_shoot = false
	aim_end = false
	move_mod = 0

func time_count():
	direction = get_direction_to_player()
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)
			head.material.set_shader_parameter("flash_opacity", 0)
			sprite_2d.material.set_shader_parameter("outline_color", line_color)
			head.material.set_shader_parameter("outline_color", line_color)
	
	if knockback_time > 0:
		knockback_time -= 1
		if knockback_time <= 0:
			body_end_knockback()
	
	if aim > 0:
		aim -= 1
		if aim <= 0:
			can_shoot = true
	
	if shoot_cd > 0:
		shoot_cd -= 1
	
	if decision_time > 0:
		decision_time -= 1
		if decision_time <= 0:
			dir_v = get_distance_to_player()
			shoot_and_move_speed = shoot_and_move * stats.MAX_SPEED
			decision_time = 5

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	
	head_look_player()
	
	if enemy_body.size() != 0:
		for i in enemy_body:
			i.velocity += i.stats.weigth_mult * (i.global_position - self.global_position).normalized() * stats.MAX_SPEED / max(0.5, i.global_position.distance_to(self.global_position))
	
	if aim_end == false:
		gun.look_at(player.global_position)
	
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

func head_look_player():
	if player != null:
		head_look = (player.global_position - global_position).normalized().angle()
		if head_look < -PI/2:
			head_look = -PI - head_look
		elif head_look > PI/2:
			head_look = PI - head_look
		head.rotation = clamp(-0.44,head_look,0.52)

func face_to_player():
	if player != null and self.position.distance_to(player.position) > 5 and aim_end == false:
		return (player.global_position - global_position).normalized()
	return Vector2.ZERO

func get_distance_to_player():
	distance = self.position.distance_to(player.position)
	var dir_to_player:Vector2 = (player.global_position - global_position).normalized()
	if distance > shoot_range:
		move_mod = 0
		return dir_to_player
	elif distance < back_range:
		move_mod = 0
		return -dir_to_player
	else:
		move_mod = 2
		return dir_to_player

func shoot_bullet():
	if shoot_cd <= 0 and can_shoot == true:
		aim_end = true
		gun.gun_shot()
		shoot_cd = shoot_cd_time
		can_shoot = false

func move(delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var direction = dir_v
	var look_dir = face_to_player()
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, ACCELERATION * delta)
		
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
			if can_shoot == true and aim <= 0 and shoot_cd <= aim_time :
				return State.SHOOTING
			
		State.RUNNING:
			if move_mod == 2:
				return State.AIMING
			if is_still:
				return State.IDLE
			
	return state
	
func transition_state(from:State, to: State) -> void:
	
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

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	head.material.set_shader_parameter("flash_opacity", 1)
	flash_time = 1

func rand_aim_and_move_speed():
	var num:float = randf_range(0.7,aim_and_move)
	if num < 0.3 :
		num = 0
	aim_and_move_speed = num * stats.MAX_SPEED

func surround_player():
	var num = randf_range(0,100)
	if num < surround_tendency:
		aim_time = surround_time
		aim_and_move_speed = stats.MAX_SPEED

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	if body.is_in_group("Enemy")  and !enemy_body.has(body) and body != self and !body.is_in_group("EnemyPart"):
		enemy_body.append(body)
	
	if body.is_in_group("Enemy") and body != self and !body.is_in_group("EnemyPart"):
		var collosion_direction = (self.position - body.position).normalized()
		self.velocity += stats.weigth_mult * collosion_direction * stats.MAX_SPEED / 2

func _on_area_2d_body_exited(body):
	if is_idle == 1:
		return
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		if in_knockback == false:
			body.velocity = velocity.limit_length(body.stats.MAX_SPEED)

func _on_gun_shoot_end():
	aim_end = false
	pass # Replace with function body.
