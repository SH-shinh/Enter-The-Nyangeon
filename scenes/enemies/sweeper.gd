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

# 冲撞：发起前只判定一次"到玩家的直线是否无障碍"；途中不再判定，撞到墙即结束。
const CHARGE_RETRY_TICKS := 10
const CHARGE_END_CD := 50

var can_charge: bool = false
var charge_dir: Vector2 = Vector2.ZERO

var move_mode: int = 0

var charge_cd_time: int = 0
var charge_dir_time: int = 0
var charge_time: int = 0

@onready var buff_box = $%BuffBox

func _init() -> void:
	ai_role = AIRole.MELEE

# 冲撞预警/冲撞期间不参与难度阵型：避免冲锋起点被侧向偏置带跑。
func ai_formation_allowed() -> bool:
	return charge_dir_time <= 0 and charge_time <= 0

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
			_end_charge(CHARGE_END_CD)
	
	if charge_cd_time > 0:
		charge_cd_time -= 1

# 冲撞统一收尾：正常结束、撞墙结束都走这里（move_mode 只有这里会清零）。
func _end_charge(cd: int) -> void:
	_apply_outline_state()
	can_charge = false
	charge_cd_time = cd
	move_mode = 0
	charge_time = 0
	charge_dir = Vector2.ZERO
	if $AnimationPlayer != null:
		$AnimationPlayer.stop()

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
			if distance < 150 and charge_cd_time <= 0 and not can_charge:
				# 只在发起前判定一次：路线被障碍挡住就不冲，稍后重试（不逐帧重判）。
				if ai_charge_path_clear(charge_target):
					can_charge = true
				else:
					charge_cd_time = CHARGE_RETRY_TICKS

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
	# 撞到墙/障碍即结束冲撞。sweeper 根 CharacterBody2D 只与 wall / bullet_wall 碰撞，
	# 不与玩家或同类碰撞，所以这里不需要按碰撞体类型筛选。
	if charge_time > 0 and get_slide_collision_count() > 0:
		_end_charge(CHARGE_END_CD)

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
