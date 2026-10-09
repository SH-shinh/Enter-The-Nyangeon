extends EquipItem

@onready var mushroom_hat_icon = preload("res://scenes/update_item/arale_hat_icon.tscn")

func _on_equip():
	PlayerData.MAX_SPEED_mult += 0.5
	PlayerData.knockback_resis_add += 30
	PlayerData.hurt_mult_mult += 0.2
	attach_hat_icon(mushroom_hat_icon)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.MAX_SPEED_mult += 0.5
	PlayerData.hurt_mult_mult += 0.2
