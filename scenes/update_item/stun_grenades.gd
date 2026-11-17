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
	BuffRouter.apply_buff(enemy, STUN_BUFF, [1, 0.0, STUN_DURATION], item_id)
