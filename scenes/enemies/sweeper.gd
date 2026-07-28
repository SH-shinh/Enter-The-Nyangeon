extends Enemy
class_name Sweeper

enum State {
	IDLE,
	RUNNING,
	CHARGING,
	DEAD,
}

@export var charge: bool = false
@export var charge_speed_mult: float = 1

var can_charge: bool = false
var charge_dir: Vector2 = Vector2.ZERO

var move_mode: int = 0

var charge_cd_time: int = 0
var charge_dir_time: int = 0
var charge_time: int = 0

@onready var buff_box = $%BuffBox

func time_count():
	
	super.time_count()
	
	if charge_dir_time > 0:
		charge_dir_time -= 1
		if charge_dir_time <= 0:
			charge_dir = get_direction_to_player()
			charge_time = 5
	
	if charge_time > 0:
		charge_time -= 1
		if charge_time <= 0:
			sprite_2d.material.set_shader_parameter("outline_width", 0)
			can_charge = false
			charge_cd_time = 50
			move_mode = 0
	
	if charge_cd_time > 0:
		charge_cd_time -= 1

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	#sprite_2d.speed_scale = (velocity.x * velocity.x + velocity.y * velocity.y) / 6400
	if enemy_body.size() != 0:
		for i in enemy_body:
			i.velocity += i.stats.weigth_mult * (i.global_position - self.global_position).normalized() * stats.MAX_SPEED / max(0.5, i.global_position.distance_to(self.global_position))
	
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.RUNNING:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.CHARGING:
			charge_move(delta, ACCELERATION, stats.MAX_SPEED)
	
	if charge == true:
		if player != null:
			var distance = self.position.distance_to(player.position)
			if distance < 150 and charge_cd_time <= 0:
				can_charge = true

func charge_move(delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, charge_dir.x * MAX_SPEED * charge_speed_mult, charge_speed_mult * ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, charge_dir.y * MAX_SPEED * charge_speed_mult, charge_speed_mult * ACCELERATION * delta)
		
		if charge_dir.x > 0:
			graphics.scale.x = 1
		elif charge_dir.x < 0:
			graphics.scale.x = -1
	
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

func get_next_state(state: State) -> State:
	
	var is_still := velocity.x == 0 and velocity.y == 0
	if stats.hp == 0 :
		return State.IDLE
	if can_charge == true:
		return State.CHARGING
	if move_mode == 0:
		return State.RUNNING
	match state:
		
		State.IDLE:
			if not is_still:
				return State.RUNNING
			
		
		State.RUNNING:
			if is_still:
				return State.IDLE
		
		State.CHARGING:
			if can_charge == false:
				return State.IDLE
		
	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			sprite_2d.play("idle")
	
		State.RUNNING:
			can_knockback = true
			sprite_2d.play("run")
		
		State.CHARGING:
			can_knockback = false
			move_mode = 1
			get_charge_dir()
			pass
		
		State.DEAD:
			pass

func get_charge_dir():
	charge_dir = Vector2.ZERO
	if $AnimationPlayer != null:
		$AnimationPlayer.play("charge_warning")
	charge_dir_time = 15

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
