extends HitBox

var direction: Vector2 = Vector2.RIGHT
var speed: int = 100
var bullet_damage: int = 1
var knockback: int = 200
var collision_num: int = 0
var penetrate: int = 0
var kill_time: float = 110
var decay_time: float = 0
var decay_speed: int = 0
var is_decay: bool = false
var explosion_range: float = 1
var speed_time: float = 5
var shoot_bullet_num: int = 0

var is_idle: int = 1
var is_ready: bool = false

@export var pool_id: String
@export var r_speed: int = 1
var acceleration: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

var player: Node
var target_position: Vector2 = Vector2.ZERO
var has_target: bool = false
var track_targets: Array = []

@onready var missile_explosion: PackedScene = preload("res://scenes/bullet/enemy_explosion_damage.tscn")
@onready var enemy_missile = $CanvasGroup/EnemyMissile
@onready var marker_2d = $Marker2D
@onready var explosion_position = $Marker2D/ExplosionPosition
@onready var gpu_particles_2d = $Marker2D/GPUParticles2D
@onready var track_box: Area2D = $TrackBox

# 玩家会在换角色时被销毁重建；池化弹不得长期缓存旧引用（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

func _ready():
	player = PlayerRef.resolve(self)
	PoolManager.add_pool(pool_id, self)
	area_entered.connect(_on_hit_box_area_entered)
	track_box.body_entered.connect(_on_track_box_body_entered)
	track_box.body_exited.connect(_on_track_box_body_exited)
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	if GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_kill_timer_timeout)
	if GameEvents.global_time_count.is_connected(_on_bullet_decay_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_decay_timer_timeout)
	is_decay = false
	decay_time = 0
	track_targets.clear()
	has_target = false
	target_position = Vector2.ZERO
	gpu_particles_2d.emitting = false
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO

func active_state():
	if is_ready == false:
		return
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	is_decay = false
	acceleration = Vector2.ZERO
	has_target = false
	track_targets.clear()
	_apply_faction_masks()
	gpu_particles_2d.restart()
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
	self.visible = true
	set_deferred("rotation", 0)

func _apply_faction_masks():
	if source_faction == Faction.PLAYER_SIDE:
		collision_mask = 16384
		track_box.collision_mask = 8
	else:
		collision_mask = 10240
		track_box.collision_mask = 513

func _physics_process(delta):
	if is_idle == 1:
		return

	if is_decay == true and speed >= 0:
		speed -= decay_speed
		if speed < 0:
			speed = 0

	target_position = _resolve_target_position()
	if has_target:
		var dir_v := (target_position - global_position).normalized() * speed
		acceleration += (dir_v - velocity).normalized() * r_speed
		velocity += acceleration * delta
	velocity = velocity.limit_length(max(speed, 1))

	global_position += velocity * delta
	enemy_missile.v = velocity.normalized().angle()
	marker_2d.rotation = enemy_missile.v

func _resolve_target_position() -> Vector2:
	if track_targets.is_empty():
		if source_faction == Faction.PLAYER_SIDE:
			has_target = false
			return Vector2.ZERO
		var p := _ensure_player()
		if p != null:
			has_target = true
			return p.global_position
		has_target = false
		return Vector2.ZERO
	var nearest = track_targets[0]
	var nearest_dist := global_position.distance_squared_to(nearest.global_position)
	for t in track_targets:
		if t == null or not is_instance_valid(t):
			continue
		var d := global_position.distance_squared_to(t.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = t
	has_target = nearest != null and is_instance_valid(nearest)
	return nearest.global_position if has_target else Vector2.ZERO

func _on_track_box_body_entered(body: Node):
	if body == null or not is_instance_valid(body):
		return
	if source_faction == Faction.PLAYER_SIDE:
		if body.is_in_group("Enemy") and Faction.of_entity(body) == Faction.ENEMY_SIDE and not track_targets.has(body):
			track_targets.append(body)
	else:
		if Faction.of_entity(body) == Faction.PLAYER_SIDE and not track_targets.has(body):
			track_targets.append(body)

func _on_track_box_body_exited(body: Node):
	if body == null or not is_instance_valid(body):
		return
	if track_targets.has(body):
		track_targets.remove_at(track_targets.find(body))

func _on_hit_box_area_entered(hurt_box: Area2D):
	if is_idle == 1:
		return
	if hurt_box is HurtBox:
		if damage_data == null:
			return
		if not Faction.hostile_to(damage_data.source_type, Faction.of_entity(hurt_box.owner)):
			return
		add_explosion.call_deferred()
		idle_state.call_deferred()

func add_explosion():
	if damage_data == null:
		return
	var ins = PoolManager.get_pool("enemy_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = missile_explosion.instantiate()
		add_ins = true

	ins.damage_data = damage_data.duplicate(true)
	ins.global_position = explosion_position.global_position
	ins.explosion_range = explosion_range
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.is_explosion()

func bullet_kill():
	pass

func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	if kill_time > 0:
		kill_time -= 1
	else:
		add_explosion.call_deferred()
		idle_state.call_deferred()

func _on_bullet_decay_timer_timeout():
	if is_idle == 1:
		return
	if decay_time > 0:
		decay_time -= 1
	else:
		is_decay = true
