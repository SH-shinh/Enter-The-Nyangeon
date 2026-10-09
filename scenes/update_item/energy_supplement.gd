extends EquipItem

@onready var animation_player = $Node2D/AnimationPlayer


var dely_time: int = 1

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	pass

func _setup():
	player.stats.hp_changed.connect(player_hp_count)
	GameEvents.global_time_count.connect(time_count)
	player_hp_count()

func time_count():
	if dely_time > 0:
		dely_time -= 1
		if dely_time <= 0:
			if GameEvents.player_hurt_hp.is_connected(fatal_damage_health):
				GameEvents.player_hurt_hp.disconnect(fatal_damage_health)

func player_hp_count():
	if player.stats.max_hp == 1:
		if GameEvents.player_hurt_hp.is_connected(fatal_damage_health):
			GameEvents.player_hurt_hp.disconnect(fatal_damage_health)
		return

	if player.stats.hp == player.stats.max_hp:
		if !GameEvents.player_hurt_hp.is_connected(fatal_damage_health):
			GameEvents.player_hurt_hp.connect(fatal_damage_health)
	else:
		dely_time = 1

func fatal_damage_health(hurt_hp: int):
	if player.stats.max_hp <= 1:
		return
	if player.stats.hp <= 0:
		player.stats.hp = 1
		if !animation_player.is_playing():
			animation_player.play("new_animation")
			SoundManager.play_sfx("EquipSounds3")
