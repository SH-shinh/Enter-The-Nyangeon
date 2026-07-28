extends RayCast2D

@onready var line_2d_2: Line2D = $Line2D2
@onready var line_2d: Line2D = $Line2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D

@export var bullet_damage: float = 12
@export var bullet_knockback: int = 80

var player: Node
var can_add_damage: bool = false
var bullet_damage_mult: float = 1
var damage_cd: int = 0

func _ready() -> void:
	GameEvents.global_time_count.connect(time_count)
	GameEvents.game_over.connect(game_over_stop_sounds)

func game_over_stop_sounds(_player_dead:bool):
	stop_sounds()

func stop_sounds():
	SoundManager.stop_sfx("LaserSounds")

func _physics_process(delta: float) -> void:
	update_poin(get_bullet_position())

func get_bullet_position():
	if is_colliding():
		var l = (get_collision_point() - global_position).length()
		return Vector2(l, 0)
	return Vector2.ZERO

func update_poin(end_point: Vector2):
	line_2d.points[1] = end_point
	line_2d_2.points[1] = end_point
	gpu_particles_2d.position = end_point
	gpu_particles_2d_2.position = end_point
	collision_shape_2d.shape.size.x = end_point.x
	collision_shape_2d.position.x = end_point.x / 2.0

func time_count():
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_damage()
			if can_add_damage:
				damage_cd = 1

func laser_warning():
	animation_player.play("warning_anim")

func laser_shoot():
	SoundManager.play_sfx("LaserSounds")
	animation_player.play("laser_anim")

func laser_end():
	SoundManager.stop_sfx("LaserSounds")
	animation_player.play_backwards("laser_anim")

func add_damage():
	if player != null and player._is_on_floor():
		player.hurt_damage = bullet_damage * bullet_damage_mult
		player.hurt_knockback = bullet_knockback
		player.hurt_dir = (player.global_position - self.global_position ).normalized()
		player.emit_signal("is_hurt")

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		if player == null:
			player = body
		can_add_damage = true
		damage_cd = 1

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		can_add_damage = false
