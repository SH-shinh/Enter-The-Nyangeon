extends EquipItem

# 震撼弹：敌人被施加感电时眩晕 0.5 秒。
# 触发源：GameEvents.enemy_shock_applied —— 由 BuffManagerBase 在「正常施加 / 满层刷新 / 来源满层刷新」
# 时发出；chihiro 释放的直写刷新（chihiro_ps.release_static）会在调用处手动补发。
# 防永久控在 buff 层（stun.tres 的 reapply_cooldown = 1.5），这里不自建冷却。

const STUN_BUFF: Buff = preload("res://resources/buff/stun.tres")
const STUN_DURATION: float = 0.5

func _setup() -> void:
	GameEvents.enemy_shock_applied.connect(_on_enemy_shock_applied)

func _on_enemy_shock_applied(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.get("is_idle") == 1:
		return
	# 重施冷却预判（与 BuffManagerBase.apply_buff 内判定同源）：满层/高频施加会让本回调
	# 每次感电都跑一遍，冷却内直接返回，避免 BuffRouter 的路由 + hook + manager 解析开销。
	var manager = enemy.get("enemy_buff_manager")
	if manager != null and manager.has_method("is_reapply_blocked") and manager.is_reapply_blocked(STUN_BUFF):
		return
	BuffRouter.apply_buff(enemy, STUN_BUFF, [1, 0.0, STUN_DURATION], item_id)
