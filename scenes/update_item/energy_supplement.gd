extends Node2D

@onready var animation_player = $Node2D/AnimationPlayer

var num: int
var player: Node

var dely_time: int = 1

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	player.stats.hp_changed.connect(player_hp_count)
	GameEvents.global_time_count.connect(time_count)

func first_activation():
	pass

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "energy_supplement":
		return
	if current_upgrade["energy_supplement"]["quantity"] == 1:
		return
	num = current_upgrade["energy_supplement"]["quantity"]

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
	if player.stats.hp <= 0:
		player.stats.hp = 1
		if !animation_player.is_playing():
			animation_player.play("new_animation")
			SoundManager.play_sfx("EquipSounds3")
