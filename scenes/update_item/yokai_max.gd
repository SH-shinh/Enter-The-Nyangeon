extends EquipItem

@onready var yokai_max_icon: PackedScene = preload("res://scenes/update_item/yokai_max_icon.tscn")

func _on_equip():
	PlayerData.MAX_SPEED_mult += 0.2
	PlayerData.bullet_speed_mult += 0.4
	PlayerData.bullet_shoot_time_mult += 0.2
	attach_hat_icon(yokai_max_icon)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_shoot_time_mult += 0.2
