extends EnemyGun

func gun_shot():
	shoot_bullet()
	shoot_end.emit()
