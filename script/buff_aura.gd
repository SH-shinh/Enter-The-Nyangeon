class_name BuffAura
extends Area2D

## 范围 buff（光环）基类：内聚「探测友方/远端镜像 → BuffRouter 上/去 buff → 召唤物光环契约 → 失活兜底清理」。
## 子类可重写 aura_buff_for/aura_value_for 支持「按目标类型给不同 buff/数值」（如 kei：玩家 vs 召唤物）。
## 未装 coop mod 时行为与单机一致（aura_source_id 回退 "1"；"CoopSummonAura" 组无消费者）。

enum Targets { PLAYERS, SUMMONS, PLAYERS_AND_SUMMONS }

@export var buff: Buff
@export var buff_layer: int = 1
@export var buff_value: float = 0.0
@export var buff_erase_timer: float = 999.0
@export var targets: Targets = Targets.PLAYERS
# 登记为「召唤物范围光环」供 mod 扫描远端召唤物镜像并转发（未装 mod 无副作用）
@export var coop_summon_aura: bool = false
@export var active_on_ready: bool = false

var _buffed: Array = []
var _active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if coop_summon_aura:
		add_to_group("CoopSummonAura")
	set_active(active_on_ready)


# ---------------- 可重写钩子 ----------------

func aura_buff_for(_body: Node) -> Buff:
	return buff


func aura_value_for(_body: Node) -> Array:
	return [buff_layer, buff_value, buff_erase_timer]


# 召唤物光环契约（mod _tick_summon_auras 用）；子类可重写为召唤物专用值
func network_aura_buff() -> Buff:
	return buff


func network_aura_value() -> Array:
	return [buff_layer, buff_value, buff_erase_timer]


# 联机来源标识 = 本机 peer id（单机为 "1"）；apply/remove 必须成对用同一 id
func aura_source_id() -> String:
	return str(multiplayer.get_unique_id())


func is_active() -> bool:
	return _active


func set_active(active: bool) -> void:
	_active = active
	var shape := _collision_shape()
	if shape != null:
		shape.set_deferred("disabled", not active)
	if not active:
		_clear_buffed()


func _clear_buffed() -> void:
	for body in _buffed:
		if body != null and is_instance_valid(body):
			BuffRouter.remove_source(body, aura_buff_for(body), aura_source_id())
	_buffed.clear()


func _collision_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child
	return get_node_or_null("CollisionShape2D") as CollisionShape2D


# 目标判定：远端玩家镜像靠 peer_id 识别（Faction.of_entity 会把镜像判成敌方）
func _should_affect(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var is_player := body.is_in_group("Player") or body.has_meta("peer_id") or body.is_in_group("Converted")
	var is_summon := body.is_in_group("Summoned")
	match targets:
		Targets.PLAYERS:
			return is_player
		Targets.SUMMONS:
			return is_summon
		Targets.PLAYERS_AND_SUMMONS:
			return is_player or is_summon
	return false


func _on_body_entered(body: Node2D) -> void:
	if not _should_affect(body):
		return
	var b := aura_buff_for(body)
	if b == null:
		return
	BuffRouter.apply_buff(body, b, aura_value_for(body), aura_source_id())
	if not _buffed.has(body):
		_buffed.append(body)


func _on_body_exited(body: Node2D) -> void:
	if not _should_affect(body):
		return
	var b := aura_buff_for(body)
	if b == null:
		return
	BuffRouter.remove_source(body, b, aura_source_id())
	_buffed.erase(body)


# 联机契约：mod _tick_summon_auras 读本节点的位置/半径/buff/value 并转发到远端召唤物
func network_summon_aura_info() -> Dictionary:
	var shape := _collision_shape()
	var r := 0.0
	if shape != null and shape.shape is CircleShape2D:
		r = (shape.shape as CircleShape2D).radius
	return {
		"active": _active and shape != null and not shape.disabled,
		"pos": shape.global_position if shape != null else global_position,
		"radius": r,
		"buff": network_aura_buff(),
		"value": network_aura_value(),
		"source_id": aura_source_id(),
	}
