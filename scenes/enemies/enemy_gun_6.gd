extends EnemyGun

@export var shoot_count: int = 1
@export_range(0, 360) var shoot_arc: float = 0

func gun_shot():
	var first_rotation = global_rotation
	var tok := begin_burst()
	for i in shoot_count:
		
		var rand_rotation = first_rotation + randf_range(-0.5,0.5)
		global_rotation = rand_rotation
		shoot_bullet()
		
		timer.start()
		await timer.timeout
		if not burst_alive(tok):
			return
	shoot_end.emit()
