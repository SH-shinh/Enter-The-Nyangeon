extends EnemyGun

func gun_shot():
	var tok := begin_burst()
	shoot_bullet()
	timer.start()
	await timer.timeout
	if not burst_alive(tok):
		return
	shoot_bullet()
	timer.start()
	await timer.timeout
	if not burst_alive(tok):
		return
	shoot_bullet()
	shoot_end.emit()
