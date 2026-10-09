extends EquipItem

@onready var mushroom_hat_icon = preload("res://scenes/update_item/mushroom_hat_icon.tscn")

func _on_equip():
	PlayerData.bullet_damage_mult += 0.25
	PlayerData.bullet_scale_mult += 2
	PlayerData.bullet_kill_time_mult *= 0.06
	PlayerData.bullet_speed_mult *= 0.6
	PlayerData.bullet_recoil_mult += 0.3
	attach_hat_icon(mushroom_hat_icon)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_mult += 0.25
	PlayerData.bullet_kill_time_mult *= 0.9
