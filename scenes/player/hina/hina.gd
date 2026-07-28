extends Player

@onready var hina_ps: Node = $hina_ps

func _unhandled_input(event:InputEvent ) -> void:
	
	if player_stop == false:
		if event.is_action_pressed("move_jump") and can_jump == true :
			is_jump_request = true
		
		if event.is_action_pressed("pause") :
			pause_screen.show_pause()
		
		if event.is_action_pressed("fire"):
			gun.is_shoot = true
		
		if event.is_action_released("fire"):
			gun.is_shoot = false
		
		if event.is_action_pressed("kick"):
			kick.kick_start()
		
		if event.is_action_pressed("reload"):
			hina_ps._ammo_reload()
