extends EquipItem

@onready var sniper_scope_icon: PackedScene = preload("res://scenes/update_item/sniper_scope_icon.tscn")

func _on_equip():
	PlayerData.critical_luck_add += 10
	PlayerData.bullet_shoot_time_mult -= 0.1
	PlayerData.critical_damage_add += 0.25
	attach_rail_icon(sniper_scope_icon)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.critical_luck_add += 10
	PlayerData.bullet_shoot_time_mult -= 0.1
	PlayerData.critical_damage_add += 0.25
