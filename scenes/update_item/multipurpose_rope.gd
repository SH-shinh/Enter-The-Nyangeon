extends EquipItem

var equip_luck: int = 20

func pick_coin(coin: Node):
	var luck = randf_range(0,200)
	if luck < equip_luck + player.stats.luck:
		coin.pick_up = true

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	equip_luck = 20

func _setup():
	GameEvents.enemy_coin_drops.connect(pick_coin)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	equip_luck += 20
