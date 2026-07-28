extends Node2D

var num: int

var equip_luck: int = 20
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_coin_drops.connect(pick_coin)

func first_activation():
	equip_luck = 20

func pick_coin(coin: Node):
	var luck = randf_range(0,200)
	if luck < equip_luck + player.stats.luck:
		coin.pick_up = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "multipurpose_rope":
		return
	if current_upgrade["multipurpose_rope"]["quantity"] == 1:
		return
	num = current_upgrade["multipurpose_rope"]["quantity"]
	equip_luck += 20
