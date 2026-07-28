extends CharacterBody2D

signal is_hurt
signal is_dead
signal coin_done
signal is_knockback
signal hurt_count(hurt_value: int)

enum State {
	IDLE,
	HURT,
	HURTAFTER,
}

var coin:PackedScene = preload("res://scenes/item/coin.tscn")
@export var pool_id: String
@export var icon:String
@export var stats: EnemyStats
@export var charge: bool = false
@export var charge_speed_mult: float = 1
@export var line_color: Color = Color(2,2,2)

var can_charge: bool = false
var charge_dir: Vector2 = Vector2.ZERO

var is_critical_hit:bool = false
var is_fire_hit:bool = false
var is_explosion_hit:bool = false
var is_poison_hit:bool = false

var ACCELERATION:float

var move_mode: int = 0

var hurt_damage:int = 0
var hurt_knockback:int = 0
var hurt_direction:Vector2

var enemy_body: Array = []
var body_part: Array = []

@export var can_knockback: bool = false
var in_knockback: bool = false

var player: Node

var is_idle: int = 1

var knockback_time: int = 0
var charge_cd_time: int = 0
var flash_time: int = 0
var charge_dir_time: int = 0
var charge_time: int = 0
var hurt_time: int = 0
var hurtafter_time: int = 0
var in_hurt: bool = false

var direction: Vector2 = Vector2.ZERO
var first_position: Vector2 = Vector2.ZERO

@onready var sprite_2d = $Graphics/AnimatedSprite2D
@onready var graphics = $Graphics
@onready var enemy_buff_manager = $EnemyBuffManager
@onready var buff_box = $%BuffBox
@onready var collision_shape_2d = $CollisionShape2D
@onready var hp_bar: TextureProgressBar = $HPBar

#var charge_cd_timer: Timer

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	enemy_body.clear()
	is_knockback.connect(body_in_knockback)
	stats.hp_changed.connect(hp_bar_update)
	is_hurt.connect(add_hurt_time)
	PoolManager.add_pool(pool_id, self)
	active_state()
	first_position = self.global_position
	GameEvents.test_room_reset.connect(reset_position)

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	get_next_state(State.IDLE)
	enemy_body.clear()
	self.visible = false
	self.global_position = Vector2.ZERO
	collision_shape_2d.disabled = true
	enemy_buff_manager.clear_all_buff()
	set_physics_process(false)

func active_state():
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	stats.spawn_hp()
	self.visible = true
	collision_shape_2d.disabled = false
	set_physics_process(true)
	hp_bar_update()

func reset_position():
	self.global_position = first_position

func add_hurt_time():
	hurt_time = 2

func hp_bar_update():
	var v = float(stats.hp) / float(stats.max_hp)
	hp_bar.value = v

func time_count():
	
	direction = get_direction_to_player()
	
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
	
	if hurt_time > 0:
		hurt_time -= 1
	
	if hurtafter_time > 0:
		hurtafter_time -= 1
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)
			sprite_2d.material.set_shader_parameter("outline_color", line_color)
	
	if charge_cd_time > 0:
		charge_cd_time -= 1
	
	if knockback_time > 0:
		knockback_time -= 1
		if knockback_time <= 0:
			body_end_knockback()

func body_in_knockback():
	in_knockback = true
	knockback_time = 5

func body_end_knockback():
	in_knockback = false

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.HURT:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.HURTAFTER:
			move(delta, ACCELERATION, stats.MAX_SPEED)

func on_dead():
	GameEvents.emit_enemy_dead_position(self.global_position)
	stats.spawn_hp()

func get_direction_to_player():
	
	if can_knockback == true:
		if self.global_position.distance_to(first_position) > 5:
			return (first_position - global_position).normalized()
	else:
		if player != null and self.position.distance_to(player.position) > 5:
			return (player.global_position - global_position).normalized()
	return Vector2.ZERO

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
	

func move(delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	if direction.x > 0:
		graphics.scale.x = 1
	elif direction.x < 0:
		graphics.scale.x = -1
	
	if can_knockback == true:
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, ACCELERATION * delta)
		move_and_slide()

func get_next_state(state: State) -> State:
	
	match state:
		
		State.IDLE:
			if hurt_time > 0:
				return State.HURT
		
		State.HURT:
			if hurt_time <= 0:
				hurtafter_time = 10
				return State.HURTAFTER
		
		State.HURTAFTER:
			if hurt_time > 0:
				return State.HURT
			if hurtafter_time <= 0:
				return State.IDLE
		
	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			sprite_2d.play("idle")
	
		State.HURT:
			sprite_2d.play("hurt")
		
		State.HURTAFTER:
			sprite_2d.play("hurt_after")

func get_charge_dir():
	charge_dir = Vector2.ZERO
	if $AnimationPlayer != null:
		$AnimationPlayer.play("charge_warning")
	charge_dir_time = 15

func _coin_drops():
	var coin_drops = PoolManager.get_pool("coins")
	if coin_drops == null or coin_drops.is_idle == 0:
		coin_drops = coin.instantiate()
		get_tree().get_first_node_in_group("CoinRoot").add_child(coin_drops)
	
	coin_drops.global_position = self.global_position
	coin_drops.coin = self.stats.Enemy_coin
	coin_drops.pick_up = self.stats.coin_pick
	coin_drops.active_state()

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	sprite_2d.material.set_shader_parameter("outline_color", Color(2,2,2))
	flash_time = 1



func _on_damage():
	#if in_hurt == true:
		#hurt_damage += hurt_damage
	#else:
		#in_hurt = true
	GameEvents.emit_enemy_hit_position(self)
	hurt_count.emit(hurt_damage)
	
	if hurt_damage != 0:
		stats.hp -= max(1, ( hurt_damage * stats.global_hurt_damage - stats.hurt_resis ))
		hurt_damage = 0
		_hurt_flash()
	in_hurt = false
	if hurt_knockback != 0 and can_knockback == true:
		var now_knockback = max(0, hurt_knockback - stats.knockback_resis )
		self.velocity = hurt_direction * now_knockback
		is_knockback.emit()
		hurt_knockback = 0
		hurt_direction = Vector2.ZERO
	
	SoundManager.play_sfx("HurtSounds")

func _on_is_hurt():
	if is_idle == 1:
		return
	_on_damage()

func _on_enemy_stats_is_dead():
	on_dead.call_deferred()
