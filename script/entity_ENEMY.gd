extends CharacterBody2D
class_name Enemy

signal is_hurt
signal is_dead
signal coin_done
signal is_knockback

@export var pool_id: String
@export var icon:String
@export var stats: EnemyStats
@export var sprite_2d: Node
@export var graphics: Node
@export var collision_shape_2d: CollisionShape2D
@export var enemy_buff_manager: Node
@export var line_color: Color = Color(2,2,2)
@export var body_part: Array[Node]

const coin:PackedScene = preload("res://scenes/item/coin.tscn")

var is_critical_hit:bool = false
var is_fire_hit:bool = false
var is_explosion_hit:bool = false
var is_poison_hit:bool = false

var ACCELERATION:float

var hurt_damage:int = 0
var hurt_knockback:int = 0
var hurt_direction:Vector2

var enemy_body: Array = []

var can_knockback: bool = true
var in_knockback: bool = false

var player: Node

var is_idle: int = 1

var knockback_time: int = 0
var flash_time: int = 0

var direction: Vector2 = Vector2.ZERO

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	enemy_body.clear()
	is_knockback.connect(body_in_knockback)
	is_hurt.connect(_on_is_hurt)
	stats.is_dead.connect(_on_enemy_stats_is_dead)
	PoolManager.add_pool(pool_id, self)

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
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

func move(delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, ACCELERATION * delta)
		
		if direction.x > 0:
			graphics.scale.x = 1
		elif direction.x < 0:
			graphics.scale.x = -1
	
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

func get_direction_to_player():
	
	if player != null and self.position.distance_to(player.position) > 5:
		
		return (player.global_position - global_position).normalized()
	
	return Vector2.ZERO

func time_count():
	
	direction = get_direction_to_player()
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)
			sprite_2d.material.set_shader_parameter("outline_color", line_color)
	
	if knockback_time > 0:
		knockback_time -= 1
		if knockback_time <= 0:
			body_end_knockback()

func body_in_knockback():
	in_knockback = true
	knockback_time = 5

func body_end_knockback():
	in_knockback = false

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	sprite_2d.material.set_shader_parameter("outline_color", Color(2,2,2))
	flash_time = 1

func _on_damage():
	GameEvents.emit_enemy_hit_position(self)
	
	if hurt_damage != 0:
		stats.hp -= max(1, ( hurt_damage * stats.global_hurt_damage - stats.hurt_resis ))
		hurt_damage = 0
		_hurt_flash()
	
	if hurt_knockback != 0 and can_knockback == true:
		var now_knockback = max(0, hurt_knockback - stats.knockback_resis )
		if now_knockback > 0:
			self.velocity = hurt_direction * now_knockback
		hurt_knockback = 0
	
	SoundManager.play_sfx("HurtSounds")

func _coin_drops():
	if stats.Enemy_coin > 0:
		var coin_drops = PoolManager.get_pool("coins")
		if coin_drops == null or coin_drops.is_idle == 0:
			coin_drops = coin.instantiate()
			get_tree().get_first_node_in_group("CoinRoot").add_child(coin_drops)
		
		coin_drops.global_position = self.global_position
		coin_drops.coin = self.stats.Enemy_coin
		coin_drops.pick_up = self.stats.coin_pick
		coin_drops.active_state()

func on_dead():
	GameEvents.emit_enemy_dead_position(self.global_position)
	idle_state.call_deferred()

func _on_is_hurt():
	if is_idle == 1:
		return
	_on_damage()

func _on_enemy_stats_is_dead():
	_coin_drops.call_deferred()
	on_dead.call_deferred()
