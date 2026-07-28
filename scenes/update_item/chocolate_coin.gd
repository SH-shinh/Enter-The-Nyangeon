extends Node2D

@onready var floating = preload("res://ui/floating_text.tscn")

var num: int
var player: Node

var coin_num: int = 0
var add_coin: int = 1

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_pick_up_coin.connect(add_coin_count)

func first_activation():
	add_coin = 1
	PlayerData.pick_up_range_mult += 0.25
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "chocolate_coin":
		return
	if current_upgrade["chocolate_coin"]["quantity"] == 1:
		return
	num = current_upgrade["chocolate_coin"]["quantity"]
	add_coin += 1
	PlayerData.pick_up_range_mult += 0.25
	PlayerData.update_player_ability()

func add_coin_count(pick_up_position: Vector2):
	coin_num += 1
	if coin_num >= 30:
		var coin_value: int = add_coin * player.stats.coin_mult
		coin_num = 0
		player.stats.coin += coin_value
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
		ins.start("+" + str(coin_value))
		SoundManager.play_sfx("CoinSounds")
		GameEvents.emit_player_coins_get(coin_value)
