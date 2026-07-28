extends CharacterBody2D

signal is_jump
signal is_jump_end
signal self_is_idle

enum State {
	IDLE,
	RUNNING,
	JUMP,
}

@export var stats: SummonedStats
@export var gun: Node
@export var long_hair: bool = false

@onready var sprite_2d: AnimatedSprite2D = %AnimatedSprite2D
@onready var smoke: GPUParticles2D = $GPUParticles2D
@onready var jump_anim: AnimationPlayer = $jump_anim
@onready var jump_dely: Timer = $jump_dely
@onready var halo_root: Node2D = %HaloRoot
@onready var halo: Sprite2D = %Halo
@onready var graphics: Node2D = %Graphics
@onready var buff_box: HBoxContainer = %BuffBox
@onready var summoned_buff_manager: Node = $SummonedBuffManager
@onready var margin_container: MarginContainer = $MarginContainer

var can_move: bool = true
var ACCELERATION: float
var player: Node
var direction: Vector2
var is_jump_request: bool = false
var spawn_point: Vector2 = Vector2(704, 448)
var enemy_body: Array =[]

var crosshair_pos: Vector2
var hurt_dir: Vector2
var hurt_knockback: int
var look_dir = null
var gun_shoot: bool = false

var is_idle: int = 0

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	jump_dely.timeout.connect(jump_start)
	stats.is_hurt.connect(_on_hurt)
	GameEvents.global_time_count.connect(time_count)
	GameEvents.player_jump.connect(follow_player_jump)
	GameEvents.crosshair_position.connect(get_crosshair_pos)
	if long_hair == true:
		GameEvents.screen_changed.connect(hair_line_changed)

func idle_state():
	self_is_idle.emit()
	self.visible = false
	self.global_position = Vector2(1000,1000)
	is_idle = 1
	summoned_buff_manager.is_idle = 1
	if !summoned_buff_manager.buff_poll.is_empty():
		for i in summoned_buff_manager.buff_poll.size():
			summoned_buff_manager.remove_buff(summoned_buff_manager.buff_poll[i])
	self.process_mode = Node.PROCESS_MODE_DISABLED
	GameEvents.round_end.connect(queue_free)

func time_count():
	direction = get_direction_to_player()

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func hair_line_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func _unhandled_input(event:InputEvent ) -> void:
	
	if can_move:
		if event.is_action_pressed("fire"):
			gun_shoot = true
		if event.is_action_released("fire"):
			gun_shoot = false

func tick_physics(state: State, delta: float) -> void:
	if is_idle == 1:
		return
	
	ACCELERATION = stats.summoned_speed / stats.SPEED_TIME
	
	if can_move == true:
		match state:
			State.IDLE:
				move(0.0, delta, ACCELERATION, stats.summoned_speed)
				
			State.RUNNING:
				move(0.0, delta, ACCELERATION, stats.summoned_speed)
				
			State.JUMP:
				move(0.0, delta, ACCELERATION * 0.5, stats.summoned_speed)
	
	gun.position.y = sprite_2d.position.y + 9
	halo_root.position.y = sprite_2d.position.y - 17
	margin_container.position.y = sprite_2d.position.y - 40
	
	if long_hair == true:
		$GraphicsGun.scale.x = graphics.scale.x
		$GraphicsHalo.scale.x = graphics.scale.x
	
	if halo.position.distance_to(halo_root.position) > 0:
		halo.position = lerp(halo.position, halo_root.position, 5 * delta)
	
	if enemy_body.is_empty():
		set_player_lookat(crosshair_pos)
		if gun != null:
			gun.look_at(crosshair_pos)
			if gun_shoot:
				gun._shoot()
	else:
		var enemy_position = enemy_body[0].global_position
		set_player_lookat(enemy_position)
		if gun != null:
			gun.look_at(enemy_position)
			gun._shoot()
		
	

func get_next_state(state: State) -> State:
	var is_floor := sprite_2d.position.y == -17
	var is_still := velocity.x == 0 and velocity.y == 0 and is_floor
	
	if is_jump_request == true and is_floor:
		return State.JUMP
	
	match state:
		
		State.IDLE:
			if not is_still:
				return State.RUNNING
			
		
		State.RUNNING:
			if is_still:
				return State.IDLE
			
		
		State.JUMP:
			if is_jump_request == false:
				return State.IDLE

	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			z_index = 0
			sprite_2d.play("idle")
			smoke.emitting = false
	
		State.RUNNING:
			sprite_2d.play("run")
			smoke.emitting = true
		
		State.JUMP:
			z_index = 3
			sprite_2d.play("jump")
			jump_anim.play("jump_anim")
			smoke.emitting = false
			GameEvents.emit_summoned_jump(self.global_position)
			is_jump.emit()

func set_player_lookat(dir):
	if dir != null:
		look_dir = sprite_2d.global_position + (dir * 1000)
		if dir.x > position.x :
			graphics.scale.x = 1
			halo.flip_h = false

		elif dir.x < position.x :
			graphics.scale.x = -1
			halo.flip_h = true

	else:
		look_dir = null

func move(gravity: float, delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, ACCELERATION * delta)
	velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, ACCELERATION * delta)
	
	move_and_slide()
	
	var collision = get_last_slide_collision()
	if collision:
		if velocity.length() > (stats.summoned_speed * 2):
			velocity = velocity.bounce(collision.get_normal()) * 0.4

func get_direction_to_player():
	if player != null and self.position.distance_to(player.position) > 50:
		if is_idle == 0:
			return (player.global_position - global_position).normalized()
	return Vector2.ZERO

func jump_start():
	is_jump_request = true

func jump_end():
	is_jump_end.emit()
	is_jump_request = false

func follow_player_jump(_position: Vector2):
	var rand_time = randf_range(0.1, 0.4)
	jump_dely.wait_time = rand_time
	jump_dely.start()

func sort_enemy():
	if enemy_body.size() != 0:
		enemy_body.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func _on_hurt():
	if hurt_knockback > 0:
		self.velocity = hurt_dir * hurt_knockback
		hurt_knockback = 0
