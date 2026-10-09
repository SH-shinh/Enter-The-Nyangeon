extends EquipItem

func _on_equip():
	PlayerData.bullet_penetrate_add += 1000
	PlayerData.bullet_speed_mult -= 0.9
	PlayerData.bullet_scale_mult += 1
	PlayerData.max_bullet_speed = 150
	PlayerData.bullet_shoot_time_mult -= 0.5
