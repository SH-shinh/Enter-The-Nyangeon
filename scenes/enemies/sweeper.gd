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
			_apply_outline_state()
			can_charge = false
			charge_cd_time = 50
			move_mode = 0
	
	if charge_cd_time > 0:
		charge_cd_time -= 1

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.move_acceleration()
	#sprite_2d.speed_scale = (velocity.x * velocity.x + velocity.y * velocity.y) / 6400
	apply_soft_collision()
	
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.RUNNING:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.CHARGING:
			charge_move(delta, ACCELERATION, stats.MAX_SPEED)
	
	if charge == true:
		var charge_target := get_target() as Node2D
		if charge_target != null and not is_standby():
			var distance = self.position.distance_to(charge_target.position)
			if distance < 150 and charge_cd_time <= 0:
				can_charge = true

func charge_move(delta: float, acceleration_local: float ,MAX_SPEED: float ) -> void:
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, charge_dir.x * MAX_SPEED * charge_speed_mult, charge_speed_mult * acceleration_local * delta)
		velocity.y = move_toward(velocity.y, charge_dir.y * MAX_SPEED * charge_speed_mult, charge_speed_mult * acceleration_local * delta)
		
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

func transition_state(_from:State, to: State) -> void:
	
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
