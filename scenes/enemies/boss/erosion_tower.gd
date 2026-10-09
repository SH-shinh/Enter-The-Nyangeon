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
	stop_shoot.connect(func(): GameEvents.emit_boss_event("erosion_tower_stop_shoot", {}))
	tower_dead.connect(func(_body): GameEvents.emit_boss_event("erosion_tower_dead", {}))
	GameEvents.boss_event.connect(_on_network_boss_event)


# 联机：可视动画态广播给其它端；远程镜像回放（host 本机已直接播放）
var _net_visual_replaying: bool = false

func _net_boss_visual(fn_name: String) -> void:
	if _net_visual_replaying:
		return
	GameEvents.emit_boss_event("erosion_tower_visual", {"fn": fn_name})


func _on_network_boss_event(event_name: String, data: Dictionary) -> void:
	# 自身或父节点（塔组）带远端标记均视为镜像：network_remote_enemy 只打在塔组根，子塔据此判定
	var remote: bool = has_meta("network_remote_enemy")
	if not remote and get_parent() != null:
		remote = get_parent().has_meta("network_remote_enemy")
	if not remote:
		return
	if event_name != "erosion_tower_visual":
		return
	var fn: String = str(data.get("fn", ""))
	if fn == "" or not has_method(fn):
		return
	_net_visual_replaying = true
	call(fn)
	_net_visual_replaying = false

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
	ACCELERATION = stats.move_acceleration()
	
	apply_soft_collision()
	
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
	
	var _is_still := velocity.x == 0 and velocity.y == 0
	
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

func transition_state(_from:State, to: State) -> void:
	
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

func shooting_state(_type: int):
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
		launcher_pool_1[n].bullet_damage_mult = stats.Enemy_damage_mult
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
	if PoolManager.active_enemy_count > 15:
		return
	enemy_spawn_launcher.hp_mult = stats.max_hp_mult
	enemy_spawn_launcher.damage_mult = stats.Enemy_damage_mult
	enemy_spawn_launcher.spawn_enemy(spawn_index)
	spawn_index = clamp(spawn_index + 1, 0, 2)

func on_dead():
	if is_idle == 1:
		return
	stop_shoot.emit()
	tower_dead.emit(self)
	boss_death_anim()

func boss_death_anim():
	_net_boss_visual("boss_death_anim")
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	enemy_body.clear()
	collision_shape_2d.set_deferred("disabled", true)
	hurt_box_shape_2d.set_deferred("disabled", true)
	enemy_buff_manager.clear_all_buff()
	animation_player_1.play("RESET")
	animation_player_2.play("dead")
	animation_player_3.play("dead")

func enter_anim():
	_net_boss_visual("enter_anim")
	animation_player_1.play("RESET")
	animation_player_2.play("RESET")
	animation_player_3.play("enter_anim")

func idle_anim():
	_net_boss_visual("idle_anim")
	animation_player_1.play("RESET")
	animation_player_2.play("idle")
	animation_player_3.play("idle")

func attack_anim():
	_net_boss_visual("attack_anim")
	animation_player_1.play("attack_anim")
	animation_player_2.play("idle")
	animation_player_3.play("attack_anim")

func defense_anim():
	_net_boss_visual("defense_anim")
	SoundManager.play_sfx("LaserSounds1")
	animation_player_1.play("RESET")
	animation_player_2.play("idle")
	animation_player_3.play("defense_mod")
	defense_animation.play("defense_shield_anim")

func _on_enemy_stats_is_dead() -> void:
	on_dead.call_deferred()
