class_name KotamaHologram
extends Node2D

## Kotama 全息影像：箱子打开 → 单团烟雾 → 角色显影；不受伤、不阻挡。
## 通过 ThreatAggro 权重调度吸引敌人；破隐后由 KotamaPS 调 start_linger() 延迟消失。

signal despawn_started

const SMOKE_FRAMES := preload("res://scenes/effects/kotama_smoke_frames.res")
const SMOKE_SOUND := "SmokeSounds"

const BOB_BASE_Y: float = -28.0
const SMOKE_WAIT: float = 0.95
const GLOW_ALPHA: float = 0.24
const GROUND_ALPHA: float = 0.14
const GLOW_SCALE := Vector2(1.1, 1.0)
const GROUND_SCALE := Vector2(1.5, 0.40)

@export var attract_radius: float = 640.0
## 主全息 2.0；T3 处决残影在生成时设 1.4。
@export var taunt_weight: float = 2.0
## 远端网络代理为 false，避免每个客户端重复播放烟雾音效。
@export var play_smoke_sound: bool = true

@onready var _box: Sprite2D = $Box
@onready var _figure: Sprite2D = $Figure
@onready var _smoke: AnimatedSprite2D = $Smoke
@onready var _projection_glow: Sprite2D = $ProjectionGlow
@onready var _ground_glow: Sprite2D = $GroundGlow
@onready var _orbit: Node2D = $OrbitParticles

var _despawn_at_msec: int = 0
var _despawning: bool = false
var _glow_energy: float = 0.0

func _ready() -> void:
	var aggro := get_node_or_null("/root/ThreatAggro")
	if aggro != null:
		aggro.call("register", self, taunt_weight, attract_radius)
	_smoke.sprite_frames = SMOKE_FRAMES
	_smoke.visible = false
	_smoke.animation_finished.connect(_hide_smoke)
	_box.frame = 0
	_projection_glow.modulate.a = 0.0
	_ground_glow.modulate.a = 0.0
	_orbit.modulate.a = 0.0
	_projection_glow.scale = GLOW_SCALE
	_ground_glow.scale = GROUND_SCALE
	var mat = _figure.material
	if mat is ShaderMaterial:
		mat.set_shader_parameter("reveal", 0.0)
	_play_open()

func _play_smoke() -> void:
	_smoke.stop()
	_smoke.frame = 0
	_smoke.visible = true
	_smoke.play("default")
	if play_smoke_sound:
		SoundManager.play_sfx(SMOKE_SOUND)

func _hide_smoke() -> void:
	_smoke.visible = false

func setup(facing_flip: bool) -> void:
	if _figure != null:
		_figure.flip_h = facing_flip

func _play_open() -> void:
	_play_smoke()
	var box_tween := create_tween()
	box_tween.tween_property(_box, "frame", 3, 0.18)
	var mat = _figure.material
	if mat is ShaderMaterial:
		var reveal_tween := create_tween()
		reveal_tween.tween_method(
			func(v: float) -> void: mat.set_shader_parameter("reveal", v),
			0.0, 1.0, 0.32
		).set_delay(0.10)
	var glow_tween := create_tween()
	glow_tween.tween_method(func(v: float) -> void: _glow_energy = v, 0.0, 1.0, 0.30)

func _process(delta: float) -> void:
	if _despawning:
		return
	_figure.position.y = BOB_BASE_Y + sin(Time.get_ticks_msec() * 0.004) * 1.2
	var pulse: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004)
	_projection_glow.modulate.a = GLOW_ALPHA * _glow_energy * pulse
	_ground_glow.modulate.a = GROUND_ALPHA * _glow_energy * pulse
	_orbit.modulate.a = _glow_energy * pulse
	_projection_glow.scale = GLOW_SCALE * (1.0 + 0.035 * (pulse - 0.85))
	_ground_glow.scale = GROUND_SCALE * (1.0 + 0.02 * (pulse - 0.85))
	if _despawn_at_msec > 0 and Time.get_ticks_msec() >= _despawn_at_msec:
		despawn()

## 破隐后固定延迟消失；0 秒仍立即走烟雾表现（供异常/外部调用兜底）。
func start_linger(seconds: float) -> void:
	var wait := maxf(0.0, seconds)
	if wait <= 0.001:
		despawn()
		return
	_despawn_at_msec = Time.get_ticks_msec() + int(round(wait * 1000.0))

func despawn() -> void:
	if _despawning:
		return
	despawn_started.emit()
	_despawning = true
	var aggro := get_node_or_null("/root/ThreatAggro")
	if aggro != null:
		aggro.call("unregister", self)
	_play_smoke()
	var tween := create_tween()
	tween.tween_property(_figure, "modulate:a", 0.0, 0.20)
	tween.parallel().tween_property(_box, "modulate:a", 0.0, 0.20)
	var glow_tween := create_tween()
	glow_tween.tween_property(_projection_glow, "modulate:a", 0.0, 0.20)
	glow_tween.parallel().tween_property(_ground_glow, "modulate:a", 0.0, 0.20)
	glow_tween.parallel().tween_property(_orbit, "modulate:a", 0.0, 0.20)
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	await tree.create_timer(SMOKE_WAIT).timeout
	if is_instance_valid(self):
		queue_free()

func _exit_tree() -> void:
	var aggro := get_node_or_null("/root/ThreatAggro")
	if aggro != null:
		aggro.call("unregister", self)
