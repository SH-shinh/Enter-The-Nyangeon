extends Node2D

var num: int
var chance: float = 5.0
@onready var BANANA: PackedScene = preload("res://scenes/banana.tscn")

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_gun_shoot.connect(add_banana)

func first_activation():
	PlayerData.max_ammo_add += 8
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "banana_magazine":
		return
	if current_upgrade["banana_magazine"]["quantity"] == 1:
		return
	num = current_upgrade["banana_magazine"]["quantity"]
	PlayerData.max_ammo_add += 8
	chance *= 1.1
	PlayerData.update_player_ability()

func add_banana(gun: Node):
	if randf_range(0, 100) < chance:
		var banana = BANANA.instantiate()
		banana.position = gun.shoot_position.global_position
		get_tree().root.add_child(banana)
