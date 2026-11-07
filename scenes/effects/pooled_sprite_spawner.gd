extends Node2D

## 共用的一次性精灵池：循环复用 AnimatedSprite2D。
## `attach_to_target = true` 时，`set_target()` 会把整池迁到目标节点下（跟随移动）；
## 否则精灵留在本节点（世界坐标投放）。

@export var frames: SpriteFrames
@export var origin := Vector2.ZERO
@export var sprite_scale := 1.0
@export var pool_cap := 4
@export var attach_to_target := false
@export var sprite_z := -1
@export var jitter := Vector2(3, 2)

var target: Node2D = null

var _pool: Array[AnimatedSprite2D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = int(hash(get_instance_id()))
	for i in pool_cap:
		_pool.append(_make())


func _make() -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.centered = false
	s.offset = -origin
	s.scale = Vector2(sprite_scale, sprite_scale)
	s.z_index = sprite_z
	s.visible = false
	add_child(s)
	s.animation_finished.connect(_on_done.bind(s))
	return s


## 设置跟随目标（仅 attach_to_target 时生效），并把整池一次性迁过去。
func set_target(node: Node2D) -> void:
	target = node
	if not attach_to_target or target == null:
		return
	for s in _pool:
		if is_instance_valid(s) and s.get_parent() != target:
			s.reparent(target)


func spawn() -> void:
	var s := _take()
	if s == null:
		s = _make()
		_pool.append(s)
		if attach_to_target and target != null and is_instance_valid(target):
			s.reparent(target)
	var parent: Node2D = target if attach_to_target and target != null and is_instance_valid(target) else self
	if s.get_parent() != parent:
		s.reparent(parent)
	s.position = Vector2(
		_rng.randf_range(-jitter.x, jitter.x),
		_rng.randf_range(-jitter.y, jitter.y))
	s.visible = true
	s.play("default")


func clear() -> void:
	for s in _pool:
		if is_instance_valid(s):
			s.stop()
			s.visible = false


func _take() -> AnimatedSprite2D:
	for s in _pool:
		if is_instance_valid(s) and not s.visible:
			return s
	return null


func _on_done(s: AnimatedSprite2D) -> void:
	if not is_instance_valid(s):
		return
	s.stop()
	s.visible = false
