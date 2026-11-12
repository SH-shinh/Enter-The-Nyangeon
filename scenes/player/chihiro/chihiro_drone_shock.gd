extends Node
## Chihiro 无人机感电导管：常驻感电，作为 ShockChain 的链节点；
## 链经过时只出电弧、不对无人机结算伤害。
##
## ShockChain 的候选池会对 shock_conduit 组件跳过 stats/health 过滤，
## 因此无人机不需要 stats / health_component 也能进链。

const SHOCK_BUFF := preload("res://resources/buff/enemy_buff/shock_dot.tres")
const TIER_LAYERS: Array[int] = [8, 9, 10, 12]

var shock_conduit: bool = true

var body: Node2D
var _layer: int = 8
var _entry: Dictionary = {}
var _active: bool = false
var _lan: bool = false


func _ready() -> void:
	body = get_parent() as Node2D
	if body != null and bool(body.get("visual_only")):
		_active = false
		return
	_entry = {
		"resource": SHOCK_BUFF,
		"layer": _layer,
		"stop": false,
		"shock_cd": ShockChain.interval_ticks_for(_layer),
	}
	_active = true
	# 联机下无人机不进链（远端没有同名导管节点，链节点序列会分叉）。
	_lan = bool(ExtensionHooks.intercept_named("is_lan_session", []))
	if not _lan:
		add_to_group("ShockCarrier")
	if not GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.connect(_on_global_tick)


func _exit_tree() -> void:
	_active = false
	if is_in_group("ShockCarrier"):
		remove_from_group("ShockCarrier")
	if GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.disconnect(_on_global_tick)


func set_tier(t: int) -> void:
	_layer = TIER_LAYERS[clampi(t, 0, TIER_LAYERS.size() - 1)]
	if _entry.is_empty():
		return
	_entry["layer"] = _layer
	_entry["shock_cd"] = ShockChain.interval_ticks_for(_layer)


func get_shock_entry() -> Dictionary:
	if not _active:
		return {}
	if body == null or not is_instance_valid(body):
		return {}
	if bool(_entry.get("stop", false)) or int(_entry.get("layer", 0)) <= 0:
		return {}
	return _entry


func reset_shock_cd() -> void:
	if _entry.is_empty():
		return
	_entry["shock_cd"] = ShockChain.interval_ticks_for(int(_entry.get("layer", 1)))


## 导管不受伤：链命中时只出视觉（由 ShockChain 统一出电弧），不结算伤害。
func shock_chain_hit(_decay: float, _knockback_dir: Vector2 = Vector2.ZERO) -> void:
	pass


func add_shock_vuln() -> void:
	pass


func replay_shock_hit(_knockback_dir: Vector2 = Vector2.ZERO) -> void:
	pass


func _on_global_tick() -> void:
	if not _active or body == null or not is_instance_valid(body):
		return
	# 与玩家/召唤物侧感电一致：联机下本地链不跑，避免两端分叉。
	if _lan:
		return
	var cd := int(_entry.get("shock_cd", 0)) - 1
	cd = mini(cd, ShockChain.interval_ticks_for(int(_entry.get("layer", 1))))
	_entry["shock_cd"] = maxi(0, cd)
	if cd > 0:
		return
	ShockChain.tick(self, body, _entry)
