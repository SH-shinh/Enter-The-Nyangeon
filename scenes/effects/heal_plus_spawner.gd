extends Node2D

## 在世界坐标生成 heal "+"（不跟随玩家）。
##
## 节点池：预热 POOL_CAP 个 AnimatedSprite2D 循环复用，正常流程零分配/零释放。
## - 常态每 0.8–1.2s 冒一个**小号**，最多同时 max_idle 个；
## - 回血 `burst()` 成簇冒**大号** + 小号。

const SMALL := preload("res://scenes/effects/heal_plus_small.res")
const BIG := preload("res://scenes/effects/heal_plus_big.res")
## 与 pixelfx_heal_plus.gd 的 meta.origin 对应（改效果尺寸时同步）
const ANCHOR := Vector2(20, 56)
const RADIUS := 85.0
## 7 大 + 6 小（burst） + 3 常态，留余量
const POOL_CAP := 18

@export var idle_min := 0.8
@export var idle_max := 1.2
@export var max_idle := 3

var _rng := RandomNumberGenerator.new()
var _timer: Timer
var _free: Array[AnimatedSprite2D] = []
var _active: Array[AnimatedSprite2D] = []
var _idle_alive := 0


func _ready() -> void:
	_rng.seed = int(hash(get_instance_id()))
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_idle)
	for i in POOL_CAP:
		_free.append(_make_sprite())
	_schedule()


## 建一个池内 sprite：一次性接好 animation_finished，之后只复用不再建。
func _make_sprite() -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.centered = false
	sprite.z_index = 2
	sprite.visible = false
	add_child(sprite)
	sprite.top_level = true
	sprite.animation_finished.connect(_on_done.bind(sprite))
	return sprite


func _schedule() -> void:
	_timer.start(_rng.randf_range(idle_min, idle_max))


func _on_idle() -> void:
	if _idle_alive < max_idle:
		_spawn(SMALL, true, 0.35, 0.90)
	_schedule()


## 回血：大号 7 个 + 小号 6 个，错开 0–0.2s。
func burst() -> void:
	for i in 7:
		_spawn(BIG, false, 0.25, 0.90, float(i) * 0.03)
	for i in 6:
		_spawn(SMALL, true, 0.30, 0.95, float(i) * 0.05)
	_schedule()


func _spawn(frames: SpriteFrames, is_small: bool, r_min: float, r_max: float, delay := 0.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(self):
			return
	var sprite := _take()
	var ang := _rng.randf() * TAU
	var r := RADIUS * sqrt(_rng.randf_range(r_min * r_min, r_max * r_max))
	sprite.sprite_frames = frames
	sprite.set_meta("is_small", is_small)
	sprite.global_position = global_position + Vector2(cos(ang), sin(ang)) * r - ANCHOR
	sprite.visible = true
	sprite.play("default")
	_active.append(sprite)
	if is_small:
		_idle_alive += 1


func _take() -> AnimatedSprite2D:
	if not _free.is_empty():
		return _free.pop_back()
	return _make_sprite()


func _on_done(sprite: AnimatedSprite2D) -> void:
	sprite.stop()
	sprite.visible = false
	_active.erase(sprite)
	if bool(sprite.get_meta("is_small", false)) and _idle_alive > 0:
		_idle_alive -= 1
	if _free.size() < POOL_CAP:
		_free.append(sprite)
	else:
		sprite.queue_free()
