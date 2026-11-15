extends Area2D

# 毒池：仿 scenes/debuff/corruption_field.gd 的场地写法。
#   - 每 tick 用形状查询收集范围内敌人 HurtBox（不依赖 area 信号，踏入即生效）；
#   - 每 poison_interval tick 给范围内敌人刷新一次毒（poison_dot）；
#   - 寿命末尾淡出，支持同点合并续命（refresh_field）；
#   - 远端视觉副本（remote_visual）只播表现，不查询也不施加。
# 视觉：$Visual 里是静态双层毒渍 + 腐化池同款冒泡（绿色重映射 shader）；
#       入场缩放只在「新池激活」播一次，同点合并续命不重播（否则看起来会不断从小变大）。

const ENEMY_HURTBOX_LAYER: int = 16384
const QUERY_MAX_RESULTS: int = 32
const FADE_TICKS: int = 15
## 入场缩放：只在 active_state() 播一次，作用于 $Visual（不缩放碰撞形状）。
const SPAWN_SCALE_FROM: float = 0.45
const SPAWN_SCALE_TIME: float = 0.18

@export var self_life: int = 80
@export var poison_buff: Buff
@export var poison_interval: int = 3
@export var poison_duration: float = 4.0
@export var poison_layer_cap: int = 1

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var visual: Node2D = $Visual

var is_idle: int = 1
var life_time: int = 0
var tick_count: int = 0
var source_id: String = ""
## 道具在 active_state() 前写入：每个毒池的毒值（桔梗人偶同口径）。
var poison_value: float = 0.0
var visual_only: bool = false
var _spawn_tween: Tween

func _ready() -> void:
	# mod 会在入树前给远端副本打 remote_visual；形状查询用的是自己的 mask，
	# 不会因为副本碰撞被清零而失效，所以必须显式短路。
	visual_only = has_meta("remote_visual")
	idle_state()

func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	_kill_spawn_tween()
	if visual != null:
		visual.scale = Vector2.ONE
	life_time = 0
	tick_count = 0
	source_id = ""
	poison_value = 0.0
	visible = false
	modulate.a = 1.0
	global_position = Vector2.ZERO
	_set_particles_emitting(false)
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled", true)
	set_deferred("monitoring", false)

func active_state() -> void:
	reset_physics_interpolation()
	is_idle = 0
	life_time = self_life
	tick_count = 0
	source_id = "poison_pool:%d" % get_instance_id()
	visible = true
	modulate.a = 1.0
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled", false)
	set_deferred("monitoring", true)
	_play_spawn_scale()
	_set_particles_emitting(true)
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)

## 同点位合并：续满寿命、保持当前视觉（不重播入场缩放），不新建节点。
func refresh_field() -> void:
	if is_idle == 1:
		active_state()
		return
	life_time = self_life
	tick_count = 0
	modulate.a = 1.0
	visible = true
	_ensure_bubbles_playing()
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)

func time_count() -> void:
	if is_idle == 1:
		return
	tick_count += 1
	if not visual_only and tick_count % maxi(1, poison_interval) == 0:
		_apply_poison()
	life_time -= 1
	if life_time <= 0:
		idle_state()
	elif life_time <= FADE_TICKS:
		modulate.a = clampf(float(life_time) / float(FADE_TICKS), 0.0, 1.0)

func _apply_poison() -> void:
	if poison_buff == null or poison_value <= 0.0:
		return
	for hurt_box in _query_hurtboxes():
		var body: Node = hurt_box.body
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if body.get("is_idle") == 1:
			continue
		if Faction.of_entity(body) != Faction.ENEMY_SIDE:
			continue
		var stats = body.get("stats")
		if stats == null or int(stats.get("hp")) <= 0:
			continue
		var manager = body.get("enemy_buff_manager")
		if manager == null:
			continue
		manager.apply_buff(poison_buff, [poison_layer_cap, poison_value, poison_duration], source_id)

func _query_hurtboxes() -> Array:
	var result: Array = []
	if collision_shape_2d == null or collision_shape_2d.shape == null:
		return result
	var space := get_world_2d().direct_space_state
	if space == null:
		return result
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_shape_2d.shape
	params.transform = collision_shape_2d.global_transform
	params.collision_mask = ENEMY_HURTBOX_LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in space.intersect_shape(params, QUERY_MAX_RESULTS):
		var hurt_box := hit.get("collider") as HurtBox
		if hurt_box != null:
			result.append(hurt_box)
	return result

## 入场缩放：只在新池激活时播一次（作用于 $Visual，不影响碰撞形状）。
func _play_spawn_scale() -> void:
	if visual == null:
		return
	_kill_spawn_tween()
	visual.scale = Vector2.ONE * SPAWN_SCALE_FROM
	_spawn_tween = create_tween()
	_spawn_tween.tween_property(visual, "scale", Vector2.ONE, SPAWN_SCALE_TIME)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _kill_spawn_tween() -> void:
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()
	_spawn_tween = null

## 续命时只保证气泡在播，不重播动画、不动缩放。
func _ensure_bubbles_playing() -> void:
	for node in find_children("*", "AnimatedSprite2D", true, false):
		var sprite := node as AnimatedSprite2D
		if sprite == null:
			continue
		sprite.visible = true
		if not sprite.is_playing():
			sprite.play("default")

func _set_particles_emitting(value: bool) -> void:
	if value:
		_ensure_bubbles_playing()
		return
	for node in find_children("*", "AnimatedSprite2D", true, false):
		var sprite := node as AnimatedSprite2D
		if sprite == null:
			continue
		sprite.visible = false
		sprite.stop()
