extends Node2D

## 狂怒词条（chip_frenzy）的敌人特效：参考 pixelfx status/rage（怒气符号 + 蒸汽 + 应力线 + 余烬 + 红光），
## 不含地面热光/裂纹，也不重绘身体。图集在运行时按敌人 hurtbox 体型对齐/缩放。
##
## 玩法接口保持原样：fit_to_enemy / begin_burn / set_burn_progress / flash_blocked / finish_burn，
## 以及头顶燃烧条（BurnBar）的 overhead 挂载逻辑。

const FALLBACK_DIAMETER := 36.0
## 效果虚拟身体高（px）：图集按 size.y / 这个值缩放
const BODY_REF_HEIGHT := 36.0
const BAR_WIDTH := 44.0
const BAR_HEIGHT := 6.0
const BAR_GAP := 2.0
## 体型测量的重算间隔（秒）；平时只做脚底跟随，避免每帧 measure
const MEASURE_INTERVAL := 0.25

## 额外的整体缩放（1.0 = 完全按体型）
@export_range(0.5, 2.0, 0.05) var visual_scale: float = 1.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _bar: ColorRect = $BurnBar

var _target_body: Node
var _bar_material: ShaderMaterial
var _burning := false
var _flash_tween: Tween
var _bar_attached_to_overhead := false
var _cached_size := Vector2.ZERO
var _cached_center := Vector2.ZERO
var _cached_body_scale := Vector2.ZERO
var _measure_wait := 0.0
var _applied_bar_size := Vector2.ZERO


func _ready() -> void:
	set_process(false)
	_bar_material = _bar.material as ShaderMaterial
	if _bar_material != null:
		_bar_material = _bar_material.duplicate() as ShaderMaterial
		_bar.material = _bar_material
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not _bar.resized.is_connected(_sync_bar_shader_size):
		_bar.resized.connect(_sync_bar_shader_size)
	_sync_bar_shader_size()
	_bar.visible = false
	_bar.modulate = Color(1, 1, 1, 0)
	_sprite.modulate = Color.WHITE
	_sprite.speed_scale = 1.0


func _exit_tree() -> void:
	if _bar != null and is_instance_valid(_bar):
		if _bar.get_parent() != self:
			if _target_body != null and is_instance_valid(_target_body) and _target_body.has_method("remove_overhead_item"):
				_target_body.remove_overhead_item(_bar)
			_bar.queue_free()
		_bar = null


func fit_to_enemy(body: Node) -> void:
	if body == null or not is_instance_valid(body) or not (body is Node2D):
		_target_body = null
		set_process(false)
		return
	_target_body = body
	_attach_bar(body)
	_measure_wait = 0.0
	_refresh_fit()
	if not _sprite.is_playing():
		_sprite.play("default")
	set_process(true)


func reset_marker() -> void:
	_burning = false
	_kill_flash_tween()
	_bar.visible = false
	_bar.modulate = Color(1, 1, 1, 0)
	_sprite.modulate = Color.WHITE
	_sprite.speed_scale = 1.0


func begin_burn(_duration: float) -> void:
	_burning = true
	_kill_flash_tween()
	_bar.visible = true
	_bar.modulate = Color(1, 1, 1, 0)
	set_burn_progress(1.0)
	var tween := create_tween()
	tween.tween_property(_bar, "modulate:a", 1.0, 0.1)
	# 濒死时心跳更急一点：稍微提速并提亮
	_sprite.modulate = Color(1.12, 1.05, 1.05, 1)
	_sprite.speed_scale = 1.25


func set_burn_progress(value: float) -> void:
	if _bar_material == null:
		return
	_bar_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func flash_blocked() -> void:
	if not _burning:
		return
	_kill_flash_tween()
	_bar.modulate = Color(1.45, 1.25, 1.0, 1)
	_sprite.modulate = Color(1.6, 1.35, 1.3, 1)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_bar, "modulate", Color(1, 1, 1, 1), 0.18)
	_flash_tween.parallel().tween_property(_sprite, "modulate", Color(1.12, 1.05, 1.05, 1), 0.18)


func finish_burn() -> void:
	_burning = false
	_kill_flash_tween()
	set_burn_progress(0.0)
	_bar.visible = false
	_bar.modulate = Color(1, 1, 1, 0)
	_sprite.modulate = Color.WHITE
	_sprite.speed_scale = 1.0


func _process(delta: float) -> void:
	if _target_body == null or not is_instance_valid(_target_body) or not (_target_body is Node2D):
		_target_body = null
		set_process(false)
		return
	_measure_wait -= delta
	_refresh_fit()


## 脚底锚定 + 按 hurtbox 高度缩放。每帧只跟随位置；体型测量按 0.25s / 缩放变化缓存。
func _refresh_fit() -> void:
	var body := _target_body as Node2D
	var body_scale := body.global_transform.get_scale()
	if _measure_wait <= 0.0 or _cached_size == Vector2.ZERO or body_scale != _cached_body_scale:
		var bounds := HurtBoxMeasure.measure(_target_body, FALLBACK_DIAMETER)
		_cached_size = bounds["size"]
		_cached_center = bounds["center"]
		_cached_body_scale = body_scale
		_measure_wait = MEASURE_INTERVAL
	position = _cached_center + Vector2(0.0, _cached_size.y * 0.5)
	var s := clampf(_cached_size.y / BODY_REF_HEIGHT, 0.8, 2.0) * clampf(visual_scale, 0.5, 2.0)
	var sc := Vector2(s, s)
	if scale != sc:
		scale = sc

	if not _bar_attached_to_overhead and _cached_size != _applied_bar_size:
		_bar.position = Vector2(-BAR_WIDTH * 0.5, -_cached_size.y - BAR_GAP - BAR_HEIGHT)
		_applied_bar_size = _cached_size


func _kill_flash_tween() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null


func _attach_bar(body: Node) -> void:
	if _bar == null or not is_instance_valid(_bar):
		return
	if body.has_method("add_overhead_item") and body.add_overhead_item(_bar):
		_bar_attached_to_overhead = true
	else:
		_bar_attached_to_overhead = false
		if _bar.get_parent() != self:
			_bar.reparent(self)
		_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_sync_bar_shader_size()


func _sync_bar_shader_size() -> void:
	if _bar_material == null or _bar == null:
		return
	var bar_size := _bar.size
	if bar_size.x <= 0.0 or bar_size.y <= 0.0:
		bar_size = _bar.custom_minimum_size
	_bar_material.set_shader_parameter("bar_size_px", bar_size)
