extends EquipItem

@onready var floating = preload("res://ui/floating_text.tscn")

var coin: int = 0
var player: Node
var reload_num: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.round_num_changed.connect(coins_count)
	GameEvents.player_ammo_reload.connect(reload_count)
	GameEvents.round_end.connect(add_coins)

func reload_count(_now_ammo: float, _max_ammo: int, _reload_time: float):
	reload_num += 1

func coins_count(now_round_num: int):
	coin = 50 * now_round_num

func add_coins():
	coin = max(0, coin * ( 1 - 0.1 * reload_num ) * player.stats.coin_mult)
	player.stats.coin += coin

	var ins = PoolManager.get_pool("floating_text")
	if ins == null or ins.is_idle == 0:
		ins = floating.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(ins)

	ins.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
	ins.set_style(Color(1,1,1), 24)
	ins.play_anim(Color(1,1,1),Color(0.986, 0.638, 0.855))
	ins.start("+" + str(coin))
	SoundManager.play_sfx("CoinSounds")

	GameEvents.emit_player_coins_get(coin)

	reload_num = 0
	coin = 0
