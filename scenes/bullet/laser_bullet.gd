extends RayCast2D

@onready var line_2d_2: Line2D = $Line2D2
@onready var line_2d: Line2D = $Line2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var hit_box = $HitBox
@onready var collision_shape_2d = $HitBox/CollisionShape2D

@export var bullet_damage: float = 12
@export var bullet_knockback: int = 80

var body_group: Array[Node]
var can_add_damage: bool = false
var bullet_damage_mult: float = 1
var damage_cd: int = 0
var is_shoot: bool = false

var source_faction: int = Faction.ENEMY_SIDE

func _ready() -> void:
	GameEvents.global_time_count.connect(time_count)
	GameEvents.game_over.connect(game_over_stop_sounds)
	hit_box.area_entered.connect(_on_hit_box_area_entered)
	hit_box.area_exited.connect(_on_hit_box_area_exited)

func game_over_stop_sounds(_player_dead:bool):
	stop_sounds()

func stop_sounds():
	SoundManager.stop_sfx("LaserSounds")

func _physics_process(_delta: float) -> void:
	update_poin(get_bullet_position())
	if is_shoot:
		SoundManager.play_loop_sfx("LaserSounds")

func get_bullet_position():
	if is_colliding():
		var l = (get_collision_point() - global_position).length()
		return Vector2(l, 0)
	return Vector2.ZERO

func update_poin(end_point: Vector2):
	line_2d.set_point_position(1, end_point)
	line_2d_2.set_point_position(1, end_point)
	gpu_particles_2d.position = end_point
	gpu_particles_2d_2.position = end_point
	collision_shape_2d.shape.size.x = end_point.x
	collision_shape_2d.position.x = end_point.x / 2.0

func time_count():
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_damage()

func laser_warning():
	animation_player.play("warning_anim")

func laser_shoot():
	is_shoot = true
	apply_damage_data()
	animation_player.play("laser_anim")

func laser_end():
	is_shoot = false
	animation_player.play_backwards("laser_anim")

func apply_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	hit_box.damage_data.base_damage = DamageRouter.scaled_damage(source_faction, bullet_damage * bullet_damage_mult, self)
	hit_box.damage_data.knockback_force = bullet_knockback
	hit_box.damage_data.knockback_direction = Vector2.RIGHT.rotated(global_rotation)
	hit_box.damage_data.damage_type.append(GameTags.BULLET_DAMAGE)
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(DamageRouter.source_tag(source_faction))

func add_damage():
	if !body_group.is_empty():
		if hit_box.damage_data != null:
			for i in body_group:
				if i == null or not is_instance_valid(i):
					continue
				i.hit_received.emit(hit_box.damage_data)
		damage_cd = 1

func _on_hit_box_area_entered(hurt_box: Area2D) -> void:
	if hurt_box is HurtBox and !body_group.has(hurt_box):
		body_group.push_back(hurt_box)
		damage_cd = 1

func _on_hit_box_area_exited(hurt_box: Area2D) -> void:
	if hurt_box is HurtBox and body_group.has(hurt_box):
		body_group.remove_at(body_group.find(hurt_box))
