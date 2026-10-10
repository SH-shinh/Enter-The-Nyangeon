extends RayCast2D

@onready var line_2d_2: Line2D = $Line2D2
@onready var line_2d: Line2D = $Line2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var hit_box = $HitBox
@onready var collision_shape_2d = $HitBox/CollisionShape2D

@export var bullet_damage: float = 12
@export var bullet_knockback: int = 100

var bullet_damage_mult: float = 1
var damage_cd: int = 0
var is_shoot: bool = false

# 结算以「即时形状查询」为准，不维护 area_entered/exited 集合：
# 边沿事件在 monitorable 切换（跳跃/闪避）时不补发，集合会残留或漏更新（LEARNINGS 556）。
var source_faction: int = Faction.ENEMY_SIDE

func _ready() -> void:
	GameEvents.global_time_count.connect(time_count)
	GameEvents.game_over.connect(game_over_stop_sounds)
	# laser_bullet 会被多个发射器和多条光束实例化，场景里的 RectangleShape2D
	# 是共享资源，多个实例每帧改写 size.x 会互相覆盖，命中框长度与可见光束不一致。
	# 每个实例复制一份自己的形状，保证命中框始终等于本条光束的长度。
	collision_shape_2d.shape = collision_shape_2d.shape.duplicate()

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
	if !is_shoot:
		return
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_damage()

func laser_warning():
	animation_player.play("warning_anim")

func laser_shoot():
	is_shoot = true
	damage_cd = 1
	apply_damage_data()
	animation_player.play("laser_anim")

func laser_end():
	is_shoot = false
	animation_player.play_backwards("laser_anim")

func apply_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"damage": DamageRouter.scaled_damage(source_faction, bullet_damage * bullet_damage_mult, self),
		"knockback": bullet_knockback,
		"direction": Vector2.RIGHT.rotated(global_rotation),
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
		"node": self,
	})

func add_damage():
	if hit_box.damage_data == null:
		return
	if collision_shape_2d.disabled:
		damage_cd = 1
		return
	# 即时重叠为准：跳跃/闪避躲出后不会被残留接触继续命中；跳回光束内也能照常结算。
	for hurtbox in _overlapping_areas():
		if hurtbox == null or not is_instance_valid(hurtbox):
			continue
		# 跳跃/闪避期 monitorable=false（set_dodge）；此期间不结算，落地且仍在光束内则恢复。
		if not hurtbox.monitorable:
			continue
		hurtbox.hit_received.emit(hit_box.damage_data)
	damage_cd = 1

# 即时重叠查询：直接问物理空间当前形状覆盖了哪些 HurtBox。
# 不用 Area2D.get_overlapping_areas()（Rapier 下会残留，LEARNINGS 321/463）。
func _overlapping_areas() -> Dictionary:
	var set: Dictionary = {}
	var space: PhysicsDirectSpaceState2D = hit_box.get_world_2d().direct_space_state
	if space == null:
		return set
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_shape_2d.shape
	params.transform = collision_shape_2d.global_transform
	params.collision_mask = hit_box.collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for r in space.intersect_shape(params, 32):
		var a = r["collider"]
		if a is HurtBox:
			set[a] = true
	return set


# 联机（仅表现端）：敌方激光对本地玩家开放伤害洞
const PLAYER_BOX_LAYER: int = 2048  # project 层 12 = player_box

func open_network_player_damage_hole() -> void:
	if source_faction == Faction.PLAYER_SIDE:
		return
	hit_box.collision_layer = 0
	hit_box.collision_mask = PLAYER_BOX_LAYER
	hit_box.monitoring = true
	hit_box.monitorable = false
	for shape in hit_box.find_children("*", "CollisionShape2D", true, false):
		var cs := shape as CollisionShape2D
		if cs != null:
			cs.disabled = false
			cs.set_deferred("disabled", false)
