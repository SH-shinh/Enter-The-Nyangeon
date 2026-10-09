extends EnemyGun

@export var shoot_count: int = 1
@export_range(0, 360) var shoot_arc: float = 0

func gun_shot():
	var first_rotation = global_rotation
	var tok := begin_burst()
	for i in shoot_count:
		
		var arc_rad = deg_to_rad(shoot_arc)
		var increment = arc_rad / (shoot_count - 1)
		
		global_rotation = (
			first_rotation +
			increment * i -
			arc_rad / 2
		)
		shoot_bullet()
		
		timer.start()
		await timer.timeout
		if not burst_alive(tok):
			return
	shoot_end.emit()
