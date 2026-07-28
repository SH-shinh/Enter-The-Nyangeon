extends Node2D

@export var pool_id: String
@export var self_life: int = 50
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var is_idle: int = 1
var value: Array
var player: Node
var player_enter: bool = false
var life_time: int

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	PoolManager.add_pool(pool_id, self)
	value = [buff_layer, buff_value, buff_erase_timer]
	GameEvents.round_end.connect(round_clear)
	GameEvents.round_upgrade.connect(round_clear)

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	self.global_position = Vector2.ZERO
	collision_shape_2d.set_deferred("disabled",true)
	set_physics_process(false)

func active_state():
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	self.visible = true
	life_time = self_life
	collision_shape_2d.set_deferred("disabled",false)
	gpu_particles_2d.restart()
	set_physics_process(true)

func time_count():
	if is_idle == 1:
		return
	
	if life_time > 0:
		life_time -= 1
		if life_time <= 0:
			idle_state()
	
	#if player_enter == true:
		#add_player_fire_dot()

func add_player_fire_dot():
	if player != null:
		player.player_buff_manager.apply_buff(player_buff, value)

func round_clear():
	PoolManager.erase_pool(pool_id)
	queue_free()

func _on_area_2d_area_shape_entered(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int) -> void:
	if area.is_in_group("PlayerBox"):
		add_player_fire_dot()

func _on_area_2d_area_shape_exited(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int) -> void:
	if area.is_in_group("PlayerBox"):
		pass
		#player_enter = false
