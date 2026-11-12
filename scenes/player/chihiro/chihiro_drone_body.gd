extends Node2D
## Chihiro 环绕无人机：跟随玩家（挂在 EquipLayer 世界层）、按世界实际移动方向倾斜、周期放电。
## 视觉：Body（机体）+ Body/Propeller（顶部中间，自转）。
## 感电触发点：ShockComponent 在 ShockCarrier 组里常驻感电（导管）。

const SHOCK_BUFF := preload("res://resources/buff/enemy_buff/shock_dot.tres")
const ARC_SCENE := preload("res://scenes/debuff/shock_chain_arc.tscn")

## 环绕半径 36.4（原 52 缩小 30%）；中心相对玩家上移 16px
const ORBIT_RADIUS: float = 36.4
const ORBIT_CENTER_OFFSET: Vector2 = Vector2(0, -16)
const ORBIT_SPEED: float = 1.4
## 倾斜上限 ±45°（按世界速度方向水平分量等比）
const TILT_MAX: float = 0.7853981633974483 # deg_to_rad(45)
## 跟随延迟：指数平滑时间常数越小越滞后
const FOLLOW_SMOOTH: float = 4.0
const ZAP_INTERVAL: Array[float] = [3.0, 3.0, 3.0, 3.0]
const ZAP_RANGE: Array[float] = [220.0, 220.0, 220.0, 220.0]
const ZAP_RATIO: Array[float] = [0.6, 0.8, 1.0, 1.3]
const ZAP_LAYERS: Array[int] = [1, 1, 2, 2]
const ARC_POWER: Array[int] = [2, 3, 4, 5]
const SHOCK_ID: String = "shock_dot"

@export var player: Node
@export var tier: int = 0
@export var phase: float = 0.0
## 镜像玩家用的纯视觉无人机：不放电、不进链
@export var visual_only: bool = false

@onready var visual: Node2D = $Visual
@onready var propeller: Sprite2D = $Visual/Body/Propeller
@onready var zap_timer: Timer = $ZapTimer
@onready var shock_component: Node = $ShockComponent

var _angle: float = 0.0
var _tier: int = 0
var _prev_global: Vector2 = Vector2.ZERO


func _ready() -> void:
	_angle = phase
	add_to_group("ChihiroDroneBody")
	if visual_only:
		_tier = clampi(tier, 0, ZAP_INTERVAL.size() - 1)
	else:
		zap_timer.timeout.connect(_zap)
		set_tier(tier)
	if _has_player():
		_snap_to_orbit()


func set_tier(t: int) -> void:
	_tier = clampi(t, 0, ZAP_INTERVAL.size() - 1)
	if visual_only:
		return
	zap_timer.wait_time = ZAP_INTERVAL[_tier]
	if zap_timer.is_inside_tree():
		zap_timer.start()
	if shock_component != null and shock_component.has_method("set_tier"):
		shock_component.call("set_tier", _tier)


## 多台均匀分布：index/count 决定相位间隔；重设后立刻对齐当前环绕点。
func set_orbit(index: int, count: int) -> void:
	phase = TAU * float(index) / float(maxi(1, count))
	_angle = phase
	if _has_player():
		_snap_to_orbit()


func _has_player() -> bool:
	return player != null and is_instance_valid(player)


func _orbit_center() -> Vector2:
	return player.global_position + ORBIT_CENTER_OFFSET


func _snap_to_orbit() -> void:
	global_position = _orbit_center() + Vector2(cos(_angle), sin(_angle)) * ORBIT_RADIUS
	_prev_global = global_position


func _process(delta: float) -> void:
	if not _has_player():
		queue_free()
		return
	_angle += ORBIT_SPEED * delta
	var center := _orbit_center()
	var target: Vector2 = center + Vector2(cos(_angle), sin(_angle)) * ORBIT_RADIUS
	global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW_SMOOTH * delta))
	# 倾斜：按世界坐标实际移动方向（含绕行 + 跟随玩家），水平分量等比映射，最大 ±45°
	var world_vel: Vector2 = (global_position - _prev_global) / maxf(delta, 0.0001)
	_prev_global = global_position
	var tilt: float = clampf(world_vel.normalized().x, -1.0, 1.0) * TILT_MAX
	visual.rotation = lerp_angle(visual.rotation, tilt, 1.0 - exp(-FOLLOW_SMOOTH * delta))
	# 螺旋桨循环自转
	propeller.rotation += 14.0 * delta


func _zap() -> void:
	if not is_inside_tree():
		return
	var stats = _player_stats()
	if stats == null:
		return
	var target: Node = _pick_target()
	if target == null:
		return
	var manager = target.get("enemy_buff_manager")
	var health = target.get("health_component")
	if manager == null or health == null:
		return
	if bool(target.get("is_idle") == 1):
		return
	var applier := _applier_stats(stats)
	for i in ZAP_LAYERS[_tier]:
		manager.apply_buff(SHOCK_BUFF, [int(stats.shock_layer), 0.0, 4.0], "chihiro_drone", applier)
	var dmg: int = maxi(1, int(round(
		float(stats.bullet_damage) * ZAP_RATIO[_tier] * float(stats.global_damage) * float(stats.dot_damage)
	)))
	var data: DamageData = DamageData.make({
		"damage": dmg,
		"type": [GameTags.SHOCK_DAMAGE, GameTags.DOT_DAMAGE],
		"source": GameTags.PS_DAMAGE,
		"node": self,
	})
	if ExtensionHooks.intercept_named("on_chihiro_drone_damage", [target, dmg, applier]):
		_spawn_arc(target)
		return
	health.request_extra_damage(data)
	_spawn_arc(target)


func _pick_target() -> Node:
	var best: Node = null
	var best_score: float = INF
	var range := ZAP_RANGE[_tier]
	for e in Targeting.candidates():
		if e == null or not is_instance_valid(e):
			continue
		if e.get("is_idle") == 1:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d > range:
			continue
		var layer := 0
		var m = e.get("enemy_buff_manager")
		if m != null and m.current_buff.has(SHOCK_ID):
			layer = int(m.current_buff[SHOCK_ID].get("layer", 0))
		# 优先未感电/低层目标，其次距离近
		var score: float = float(layer) * 1000.0 + d
		if score < best_score:
			best_score = score
			best = e
	return best


func _player_stats():
	if _has_player():
		var pstats = player.get("stats")
		if pstats != null:
			return pstats
	var p := PlayerRef.resolve(self)
	if p == null:
		return null
	return p.get("stats")


func _applier_stats(stats) -> Dictionary:
	return {
		"shock_layer": int(stats.shock_layer),
		"dot_damage": float(stats.dot_damage),
		"dot_time": float(stats.dot_time),
		"global_damage": float(stats.global_damage),
	}


func _spawn_arc(target: Node) -> void:
	if not PoolManager.fx_allowed(&"shock_chain"):
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		return
	var fx = PoolManager.get_pool("shock_chain")
	if fx == null or fx.is_idle == 0:
		fx = ARC_SCENE.instantiate()
		layer.add_child(fx)
		var sfx = fx.get_node_or_null("Sfx")
		if sfx != null:
			sfx.volume_db = -16.0
	fx.play([global_position, target.global_position + Vector2(0, -12)], ARC_POWER[_tier])
