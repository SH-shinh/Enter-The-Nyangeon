extends EquipItem

# GGC复刻版：感电层上限 +2，不限叠加。
# 层上限会同时放大链的射程、放电频率、跳数与每跳伤害（见 script/shock_chain.gd 的 range/interval/hop 公式）。

func _apply_effect(_quantity: int) -> void:
	PlayerData.shock_layer_add += 2
