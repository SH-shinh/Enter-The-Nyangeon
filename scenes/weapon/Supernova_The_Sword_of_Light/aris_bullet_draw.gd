extends Node2D
#
#@onready var laser: PackedScene = preload("res://scenes/bullet/laser_bullet.tscn")
#@onready var timer = $Timer
#
#func _ready():
	#GameEvents.player_shot_position.connect(add_bullet)
	#timer.timeout.connect(emit_laser_stop)
#
#func timer_return_zero():
	#timer.stop()
#
#func emit_laser_stop():
	#GameEvents.emit_player_laser_stop()
#
#func add_bullet(shoot_position: Vector2,now_bullet: Node):
	#if timer.time_left <= 0:
		#var ins = laser.instantiate()
		#ins.bullets.push_back(now_bullet)
		#ins.stop.connect(timer_return_zero)
		#ins.first_point = shoot_position
		#get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
		#ins.add_first_points()
	#timer.start()
