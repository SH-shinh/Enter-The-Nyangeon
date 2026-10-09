extends EnemyGun

@export var shoot_bullet_num: int = 16

func gun_shot():
	shoot_bullet()
	shoot_end.emit()
