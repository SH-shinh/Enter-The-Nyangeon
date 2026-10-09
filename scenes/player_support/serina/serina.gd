extends SupportCharacter

# serina 支援：特殊效果为医疗箱生成概率翻倍且必定落在玩家脚下、长按拾取速度 +100%；
# 被动数值（heal_mult）由 SupportCharacter 统一处理。

@export var spawn_rate_mult: float = 2.0
@export var pick_up_speed_bonus: float = 1.0

func _special_effect() -> void:
	PlayerData.pick_up_speed_mult += pick_up_speed_bonus
	PlayerData.update_player_ability()
	var pick_manager := get_tree().get_first_node_in_group("PickManager")
	if pick_manager != null:
		pick_manager.spawn_at_player = true
		pick_manager.spawn_rate_mult = spawn_rate_mult

# 联机：供 host 聚合各端支援对医疗箱生成的影响（本端单机时也直接生效，见 _special_effect）
func get_medkit_spawn_modifiers() -> Dictionary:
	return {"rate_mult": spawn_rate_mult, "at_player": true}
