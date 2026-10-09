extends EquipItem

@onready var floating = preload("res://ui/floating_text.tscn")

var player: Node

var coin_num: int = 0
var add_coin: int = 1

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	add_coin = 1
	PlayerData.pick_up_range_mult += 0.25

func _setup():
	GameEvents.player_pick_up_coin.connect(add_coin_count)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	add_coin += 1
	PlayerData.pick_up_range_mult += 0.25

func add_coin_count(pick_up_position: Vector2):
	coin_num += 1
	if coin_num >= 30:
		var coin_value: int = add_coin * player.stats.coin_mult
		coin_num = 0
		player.stats.coin += coin_value
		var ins = PoolManager.get_pool("floating_text")
		if ins == null or ins.is_idle == 0:
			ins = floating.instantiate() as Node2D
			get_tree().get_first_node_in_group("ForegroundLayer").add_child(ins)

		ins.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		ins.set_style(Color(1,1,1), 24)
		ins.play_anim(Color(1,1,1),Color(0.986, 0.638, 0.855))
		ins.start("+" + str(coin_value))
		SoundManager.play_sfx("CoinSounds")
		GameEvents.emit_player_coins_get(coin_value)
