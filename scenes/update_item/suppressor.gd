extends EquipItem

@onready var Suppressor: PackedScene = preload("res://scenes/update_item/suppressor_icon.tscn")
var muzzle_group: Array

func _on_equip():
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.bullet_knockback_mult -= 0.1
	PlayerData.bullet_recoil_mult -= 0.1
	if player != null:
		player.gun.fire_sounds.pitch_scale *= 0.7

	muzzle_group = get_tree().get_nodes_in_group("Muzzle")
	for i in muzzle_group:
		if i.muzzle_use == false:
			var sprite_2d = Suppressor.instantiate()
			i.add_child(sprite_2d)
			i.muzzle_use = true

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.bullet_knockback_mult -= 0.1
