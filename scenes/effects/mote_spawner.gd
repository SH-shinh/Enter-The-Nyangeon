extends "res://scenes/effects/pooled_sprite_spawner.gd"

## 光尘生成器：按 interval 在自身位置（世界坐标）投放 `serina_dust`。
## 精灵留在本节点下，不跟随玩家。

const FRAMES := preload("res://scenes/effects/serina_dust_frames.res")

@export var interval := 0.12

var _timer: Timer


func _ready() -> void:
	frames = FRAMES
	origin = Vector2(16, 24)
	sprite_z = 1
	pool_cap = 8
	attach_to_target = false
	super()
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = maxf(0.03, interval)
	add_child(_timer)
	_timer.timeout.connect(spawn)


func start() -> void:
	_timer.start()


func stop() -> void:
	_timer.stop()
	clear()
