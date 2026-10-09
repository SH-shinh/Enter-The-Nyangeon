extends EquipItem

@onready var tnt_icon = preload("res://scenes/update_item/tnt_icon.tscn")


func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.explosion_damage_mult += 0.55
	PlayerData.explosion_range_mult += 0.35
	attach_follow_icon(tnt_icon)

func _setup():
	GameEvents.explosion_damage.connect(explosion_knockback)

func explosion_knockback(explosion_position: Vector2, explosion_range: float):
	if explosion_position.distance_to(player.global_position) < explosion_range:
		player.hurt_dir = (player.global_position - explosion_position ).normalized()
		player.hurt_knockback = player.stats.bullet_knockback + 200
		player.is_hurt.emit()
