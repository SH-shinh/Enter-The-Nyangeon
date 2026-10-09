extends EquipItem

@onready var EXPS_3_0_ICON: PackedScene = preload("res://scenes/update_item/exps_3_0_icon.tscn")

func _on_equip():
	PlayerData.critical_luck_add += 5
	PlayerData.bullet_recoil_mult *= 0.85
	attach_rail_icon(EXPS_3_0_ICON)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.critical_luck_add += 5
	PlayerData.bullet_recoil_mult *= 0.85
