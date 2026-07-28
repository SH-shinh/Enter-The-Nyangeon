extends Node2D

@onready var floating = preload("res://ui/floating_text.tscn")

var num: int
var coin: int = 0
var player: Node
var reload_num: int = 0

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.round_num_changed.connect(coins_count)
	GameEvents.player_ammo_reload.connect(reload_count)
	GameEvents.round_end.connect(add_coins)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "intact_atlantis_medal":
		return
	if current_upgrade["intact_atlantis_medal"]["quantity"] == 1:
		return
	num = current_upgrade["intact_atlantis_medal"]["quantity"]

func reload_count(now_ammo: float, max_ammo: int, reload_time: float):
	reload_num += 1

func coins_count(now_round_num: int):
	coin = 50 * now_round_num

func add_coins():
	coin = max(0, coin * ( 1 - 0.1 * reload_num ) * player.stats.coin_mult)
	player.stats.coin += coin
	
	var ins
	
	if FloatingPool.floating_pool.size() > 100:
		ins = FloatingPool.floating_pool[0]
		ins.reset()
		FloatingPool.call_pool()
	else:
		ins = floating.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(ins)
	
	ins.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
	ins.play_anim(Color(1,1,1),Color(0.986, 0.638, 0.855))
	ins.label.set("theme_override_font_sizes/font_size", 24)
	ins.start("+" + str(coin))
	SoundManager.play_sfx("CoinSounds")
	
	GameEvents.emit_player_coins_get(coin)
	
	reload_num = 0
	coin = 0
	
