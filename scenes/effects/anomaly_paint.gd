extends Node2D
## Maki 被动「异常伤害」的地板颜料粒子：沿用 floor_paint 的三色发射器方案，
## 按异常类型（燃烧/中毒/恶寒）播放对应颜色的颜料，尺寸与铺开范围约为 floor_paint 的 50%。

const POOL_ID := "anomaly_paint"
## 10Hz tick 下 30 次 = 3s，与粒子 lifetime 对齐，避免连射时堆满长驻颜料
const ACTIVE_TICKS: int = 30

@onready var fire_particles: GPUParticles2D = $Fire
@onready var poison_particles: GPUParticles2D = $Poison
@onready var chill_particles: GPUParticles2D = $Chill

var is_idle: int = 1
var idle_time: int = ACTIVE_TICKS


func _ready() -> void:
	PoolManager.add_pool(POOL_ID, self)


func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	# 被池满强收（_recycle → idle_state）时也要停喷，避免隐形节点继续吃 GPU
	_stop_particles()
	visible = false
	global_position = Vector2.ZERO


func clear_pool() -> void:
	PoolManager.erase_pool(POOL_ID)


## element 取 GameTags.FIRE_DAMAGE / POISON_DAMAGE / CHILL_DAMAGE；未知元素回落燃烧色。
func active_state(element: String = GameTags.FIRE_DAMAGE) -> void:
	reset_physics_interpolation()
	is_idle = 0
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	idle_time = ACTIVE_TICKS
	visible = true
	_stop_particles()
	_emitter_for(element).restart()


## 联机通用视觉参数入口：远端克隆按元素重放（纯表现）。
func network_apply_visual(params: Dictionary) -> void:
	var e = params.get("element", GameTags.FIRE_DAMAGE)
	active_state(str(e) if e is String else GameTags.FIRE_DAMAGE)


func time_count() -> void:
	if idle_time > 0:
		idle_time -= 1
		if idle_time <= 0:
			idle_state()


func _emitter_for(element: String) -> GPUParticles2D:
	if element == GameTags.POISON_DAMAGE:
		return poison_particles
	if element == GameTags.CHILL_DAMAGE:
		return chill_particles
	return fire_particles


func _stop_particles() -> void:
	for p in [fire_particles, poison_particles, chill_particles]:
		if p != null:
			p.emitting = false
