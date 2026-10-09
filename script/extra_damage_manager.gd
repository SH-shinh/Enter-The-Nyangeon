extends Node

## 通用额外伤害入口（autoload: ExtraDamage）
## 调用方通过 ExtraDamage.request(target, damage_data) 发起一次独立伤害，
## 该伤害不影响当前正在结算的正常伤害，会在本次结算完成后追加。
## 注意：发起方订阅者必须过滤 GameTags.EXTRA_DAMAGE，避免递归。

func _ready():
	if not GameEvents.enemy_extra_damage_request.is_connected(_on_request):
		GameEvents.enemy_extra_damage_request.connect(_on_request)

## 公共 API：由调用方拿目标节点发起请求，自动补 EXTRA_DAMAGE 标记
func request(target: Node, damage_data: DamageData) -> void:
	if target == null or not is_instance_valid(target) or damage_data == null:
		return
	if not damage_data.flags.has(GameTags.EXTRA_DAMAGE):
		damage_data.flags.append(GameTags.EXTRA_DAMAGE)
	GameEvents.emit_enemy_extra_damage_request(target.get_path(), damage_data)

## 同步解析目标（事件本就在 take_damage 内同步发出，此刻目标一定有效），
## 交给目标 HealthComponent 的实例队列，等本次结算完成后再施加。
func _on_request(body_path: NodePath, damage_data: DamageData) -> void:
	var target = get_tree().root.get_node_or_null(body_path)
	if target == null or not is_instance_valid(target):
		return
	var hc = target.get("health_component")
	if hc != null and hc.has_method("request_extra_damage"):
		hc.request_extra_damage(damage_data)
	elif hc != null and hc.has_method("take_damage"):
		hc.take_damage.call_deferred(damage_data)
