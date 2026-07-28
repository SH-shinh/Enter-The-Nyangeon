extends Enemy
class_name ErosionTower

signal stop_shoot
signal tower_dead(body: Node)

enum State {
	IDLE,
	SHOOTING,
	DEFENSE,
	SUMMON,
	DEAD,
}

@export_range(1,3) var tower_type: int = 1
@export var launcher_pool_1: Array[Node]

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var animation_player_1: AnimationPlayer = $Graphics/Sprite2D6/AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $Graphics/Sprite2D/AnimationPlayer
@onready var animation_player_3: AnimationPlayer = $AnimationPlayer
@onready var defense_mod: Node2D = $defense_mod
@onready var defense_animation: AnimationPlayer = $defense_mod/AnimationPlayer
@onready var static_bullet_1: Node2D = $StaticBullet1
@onready var enemy_spawn_launcher: Node2D = $enemy_spawn_launcher
@onready var buff_box: HBoxContainer = %BuffBox
@onready var lock_hp: Node = $EnemyStats/LockHP

var launcher_cd: int = 0

var can_shoot: bool = false
var can_defense: bool = false
var shoot_cd: int = 0
var defense_time: int = 0

var spawn_index: int = 0

var value: Array

func _ready() -> void:
	super._ready()
	for i in launcher_pool_1:
		stop_shoot.connect(i.stop_rotating)
	stop_shoot.connect(static_bullet_1.stop_shoot)
	lock_hp.reach_value.connect(hurt_defense)

func hurt_defense(_value_index: int):
	can_shoot = false
	can_defense = true

func time_count():
	super.time_count()
	
	if shoot_cd > 0:
		shoot_cd -= 1
		if shoot_cd <= 0:
			shooting_state(tower_type)
	
	if defense_time > 0:
		defense_time -= 1
		if defense_time <= 0:
			can_defense = false
			defense_animation.play("RESET")

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	
	if enemy_body.size() != 0:
		for i in enemy_body:
			i.velocity += i.stats.weigth_mult * (i.global_position - self.global_position).normalized() * stats.MAX_SPEED / max(0.5, i.global_position.distance_to(self.global_position))
	
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, 0)
		State.SHOOTING:
			move(delta, ACCELERATION, 0)
		State.DEFENSE:
			move(delta, ACCELERATION, 0)
		State.SUMMON:
			move(delta, ACCELERATION, 0)
		State.DEAD:
			move(delta, ACCELERATION, 0)

func get_next_state(state: State) -> State:
	
	var is_still := velocity.x == 0 and velocity.y == 0
	
	if stats.hp == 0 :
		return State.DEAD
	
	match state:
		
		State.IDLE:
			if can_shoot:
				return State.SHOOTING
			if can_defense:
				return State.DEFENSE
		
		State.SHOOTING:
			if !can_shoot:
				stop_shoot.emit()
				return State.IDLE
			
		State.DEFENSE:
			if !can_defense:
				return State.IDLE
		
		State.SUMMON:
			pass
		
		State.DEAD:
			pass
		
	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			idle_anim()
		
		State.SHOOTING:
			attack_anim()
			shooting_state(tower_type)
		
		State.DEFENSE:
			can_shoot = false
			value = [buff_layer, buff_value, buff_erase_timer]
			enemy_buff_manager.apply_buff(enemy_buff, value)
			defense_anim()
			shooting_state(tower_type)
			defense_time = 100
		
		State.SUMMON:
			pass
		
		State.DEAD:
			on_dead()

func shooting_state(type: int):
	if can_shoot == false:
		if can_defense:
			spawn_shoot()
			shoot_cd = 30
		return
	match tower_type:
		1:
			laser_shoot()
		2:
			bullet_shoot()
			#shoot_cd = 60
		3:
			spawn_shoot()
			shoot_cd = 60

func laser_shoot():
	if is_idle == 1:
		return
	if !launcher_pool_1.is_empty():
		var n = randi_range(0, launcher_pool_1.size() - 1)
		launcher_pool_1[n].active_state()

func bullet_shoot():
	if is_idle == 1:
		return
	var n = randi_range(0, 1)
	static_bullet_1.can_shoot = true
	if n == 0:
		static_bullet_1.static_interlace_slow()
	else:
		static_bullet_1.static_order_slow()

func spawn_shoot():
	if is_idle == 1:
		return
	if PoolManager.enemies_group.size() > 15:
		return
	enemy_spawn_launcher.hp_mult = stats.max_hp_mult
	enemy_spawn_launcher.damage_mult = stats.Enemy_damage_mult
	enemy_spawn_launcher.spawn_enemy(spawn_index)
	spawn_index = clamp(spawn_index + 1, 0, 2)

func on_dead():
	stop_shoot.emit()
	tower_dead.emit(self)
	boss_death_anim()

func boss_death_anim():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	enemy_body.clear()
	collision_shape_2d.disabled = true
	enemy_buff_manager.clear_all_buff()
	animation_player_1.play("RESET")
	animation_player_2.play("dead")
	animation_player_3.play("dead")

func enter_anim():
	animation_player_1.play("RESET")
	animation_player_2.play("RESET")
	animation_player_3.play("enter_anim")

func idle_anim():
	animation_player_1.play("RESET")
	animation_player_2.play("idle")
	animation_player_3.play("idle")

func attack_anim():
	animation_player_1.play("attack_anim")
	animation_player_2.play("idle")
	animation_player_3.play("attack_anim")

func defense_anim():
	SoundManager.play_sfx("LaserSounds1")
	animation_player_1.play("RESET")
	animation_player_2.play("idle")
	animation_player_3.play("defense_mod")
	defense_animation.play("defense_shield_anim")

func _on_enemy_stats_is_dead() -> void:
	on_dead.call_deferred()
