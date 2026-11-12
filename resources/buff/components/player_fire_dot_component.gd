extends BuffComponent
## 玩家 / 召唤物被点燃（`player_fire_dot`）时的视觉与跳伤。
##
## 视觉与敌人燃烧共用同一份烘焙帧 `burning_aura_frames.res`（不新增显存）。
## 关键：**光环挂在角色的视觉节点下**，不是按固定坐标摆——
## 玩家的跳跃/滞空是移动 `sprite_2d.position.y` 做的假 Z（`script/player.gd:375`），
## 跳跃期间 `z_index` 还会从 0 变 3（`script/player.gd:456/467`）。
## 挂成子节点后，假 Z 跟随、`z_index`（相对）也比角色高 1，天然正确。
## 召唤物没有 `sprite_2d`，退到它的 `Graphics` 节点（同样跟随其跳跃）。

const FRAMES := preload("res://scenes/effects/burning_aura_frames.res")
## 与效果脚本 meta.origin 对应（画布 80×80，原点在身体中心）
const AURA_ORIGIN := Vector2(40, 40)
## 跳伤脉冲：0.2s 一跳，配 0.07s 的短提亮（>1 依靠项目已开启的 hdr_2d）
const PULSE_TIME := 0.07
const PULSE_TINT := Color(1.8, 1.5, 1.2, 1.0)

@onready var dot_timer: Timer = $DotTimer

var active: bool = false
var damage: float = 1.0

var _aura: AnimatedSprite2D
var _pulse_t := 0.0


func _ready() -> void:
	# 平时不跑 _process，只在脉冲期间开
	set_process(false)


func activate(entry: Dictionary) -> void:
	damage = entry["value"]
	active = true
	if not dot_timer.timeout.is_connected(_dot_damage):
		dot_timer.timeout.connect(_dot_damage)
	dot_timer.start()
	_spawn_aura()
	_dot_damage()


func refresh(_entry: Dictionary) -> void:
	if dot_timer != null:
		dot_timer.start()


func deactivate() -> void:
	active = false
	if dot_timer != null:
		dot_timer.stop()
	_pulse_t = 0.0
	set_process(false)
	_free_aura()


## 组件可能晚于角色被释放（回合清场），这里兜底，避免光环作为角色子节点残留
func _exit_tree() -> void:
	_free_aura()


func _dot_damage() -> void:
	if body == null or not active:
		return
	_pulse()
	var health_component = body.get("health_component")
	if health_component == null:
		return
	var bearer: int = Faction.of_entity(body)
	var source_faction: int = Faction.ENEMY_SIDE if bearer == Faction.PLAYER_SIDE else Faction.PLAYER_SIDE
	var ddata := DamageData.dot(int(damage), GameTags.FIRE_DAMAGE, DamageRouter.source_tag(source_faction))
	health_component.take_damage(ddata)


# ---------------- 视觉 ----------------

## 光环挂载点：玩家挂 `sprite_2d`（跳跃就是移动它），召唤物挂 `Graphics`，兜底挂自己
func _anchor_node() -> Node:
	if body != null:
		var sp = body.get("sprite_2d")
		if sp is Node2D:
			return sp
		var g := body.get_node_or_null("Graphics")
		if g is Node2D:
			return g
	return self


func _spawn_aura() -> void:
	if _aura != null and is_instance_valid(_aura):
		_aura.visible = true
		_aura.set_frame(0)
		_aura.play("default")
		return
	var host := _anchor_node()
	_aura = AnimatedSprite2D.new()
	_aura.name = "BurnAura"
	_aura.sprite_frames = FRAMES
	_aura.centered = false
	_aura.offset = -AURA_ORIGIN
	_aura.position = Vector2.ZERO
	# z_as_relative 默认开：有效 z = 角色 z + 1，跳跃（z=3）时是 4，始终在角色之上
	_aura.z_index = 1
	host.add_child(_aura)
	_aura.play("default")


func _free_aura() -> void:
	if _aura != null and is_instance_valid(_aura):
		_aura.stop()
		_aura.visible = false
		_aura.queue_free()
	_aura = null


## 跳伤反馈：手动衰减，不用 Tween（0.2s 一跳的高频场景）
func _pulse() -> void:
	if _aura == null or not is_instance_valid(_aura):
		return
	_pulse_t = 1.0
	_aura.modulate = PULSE_TINT
	set_process(true)


func _process(delta: float) -> void:
	if _pulse_t <= 0.0 or _aura == null or not is_instance_valid(_aura):
		_pulse_t = 0.0
		set_process(false)
		return
	_pulse_t = maxf(0.0, _pulse_t - delta / PULSE_TIME)
	if _pulse_t <= 0.0:
		_aura.modulate = Color.WHITE
		set_process(false)
	else:
		_aura.modulate = Color.WHITE.lerp(PULSE_TINT, _pulse_t * _pulse_t)
