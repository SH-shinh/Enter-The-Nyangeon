extends EnemyGun

@onready var animation_player = $AnimationPlayer

func emit_shoot_end():
	shoot_end.emit()

func gun_shot():
	animation_player.play("shoot_anim")
