extends CharacterBody2D

signal is_hurt
signal is_dead

@export var icon:String
@export var stats: EnemyStats

@onready var sprite_2d = $Graphics/Sprite2D
@onready var enemy_buff_manager = $EnemyBuffManager
@onready var graphics = $Graphics
@onready var collision_shape_2d = $CollisionShape2D

var player: Node
var look_at: float

var is_critical_hit:bool = false
var is_fire_hit:bool = false
var is_explosion_hit:bool = false
var is_poison_hit: bool = false

var hurt_damage:int = 0
var hurt_knockback:int = 0
var hurt_direction:Vector2

var is_idle: int = 1

var flash_time: int = 0

func _ready():
	player = get_tree().get_first_node_in_group("Player")

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	collision_shape_2d.set_deferred("disabled",true)
	enemy_buff_manager.clear_all_buff()
	set_physics_process(false)

func active_state():
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	stats.spawn_hp()
	self.visible = true
	collision_shape_2d.set_deferred("disabled",false)
	set_physics_process(true)

func _physics_process(delta):
	look_at_player()

func look_at_player():
	look_at = (player.global_position - global_position).normalized().angle()
	if look_at < -PI/2:
		look_at = -PI - look_at
	elif look_at > PI/2:
		look_at = PI - look_at
	rotation = clamp(-0.15,look_at,0.15)

func time_count():
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	flash_time = 1

func on_dead():
	GameEvents.emit_enemy_dead_position(self.global_position)
	idle_state.call_deferred()

func _on_damage():
	GameEvents.emit_enemy_hit_position(self)
	
	if hurt_damage != 0:
		stats.hp -= max(1, ( hurt_damage * stats.global_hurt_damage - stats.hurt_resis ))
		hurt_damage = 0
		_hurt_flash()
	
	SoundManager.play_sfx("HurtSounds")

func _on_is_hurt():
	if is_idle == 1:
		return
	_on_damage()

func _on_enemy_stats_is_dead():
	on_dead()
