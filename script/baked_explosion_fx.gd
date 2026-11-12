extends Node2D
## 烘焙帧爆炸视觉（大/小爆炸共用一套逻辑，靠导出属性区分）。
##
## 只做表现；范围与伤害由 `script/explosion_damage.gd` 的 `ExplosionDamage` 负责。
## 池契约不变：`is_idle` / `idle_state()` / `active_state()`，池 id 由 `pool_id` 给出
## （联机 mod 的 `_remove_effect_from_gameplay_pools` 按**场景路径**映射到池 id，不依赖脚本常量）。
##
## 两档配置见 `script/explosion.tscn`（big_explosion / explosion_big_frames / origin 112,112）
## 与 `script/small_explosion.tscn`（small_explosion / explosion_small_frames / origin 80,80）。

## 池 id：big_explosion / small_explosion（必须与 PoolManager.IDLE_LIMITS 的键一致）
@export var pool_id: String = ""
## 烘焙好的 SpriteFrames（`scenes/effects/explosion_{big,small}_frames.res`）
@export var frames: SpriteFrames
## 与效果脚本 meta.origin 一致；改画布时要同步改这里
@export var origin: Vector2 = Vector2.ZERO

var is_idle: int = 1

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	PoolManager.add_pool(pool_id, self)
	_sprite.sprite_frames = frames
	_sprite.centered = false
	_sprite.offset = -origin
	_sprite.animation_finished.connect(idle_state)
	_sprite.visible = false


func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	visible = false
	global_position = Vector2.ZERO
	if _sprite != null:
		_sprite.stop()
		_sprite.visible = false


func active_state() -> void:
	reset_physics_interpolation()
	# 只尊重「特效关」总开关，不做 50ms 间隔节流：同一帧大/小两颗爆炸都要出来
	if PoolManager.effect_freq_off():
		idle_state()
		return
	is_idle = 0
	visible = true
	_sprite.visible = true
	_sprite.set_frame(0)
	_sprite.play("default")
