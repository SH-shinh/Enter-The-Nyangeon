extends CanvasLayer

@export var up_item_card: PackedScene

@onready var card_box = %CardBox
@onready var round_num = %RoundNum
@onready var coin = %Coin
@onready var animation_player = $AnimationPlayer

var current_card: Dictionary = {}

var player: Node

func _ready():
	GameEvents.ability_upgrade_added.connect(add_player_up_item_card)
	GameEvents.round_upgrade.connect(show_player_date)
	GameEvents.round_upgrade_closing.connect(hide_player_date)
	GameEvents.round_start.connect(hide_player_date)
	GameEvents.round_num_changed.connect(next_round_num)
	GameEvents.get_player.connect(get_player)

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	if player == null:
		return
	if not player.stats.coin_changed.is_connected(update_coin):
		player.stats.coin_changed.connect(update_coin)

func update_coin():
	coin.text = str(player.stats.coin)

func next_round_num(now_round_num: int):
	round_num.text = str(now_round_num + 1)

func show_player_date():
	self.visible = true
	animation_player.play("date_in_anim")
	update_coin()

func hide_player_date():
	self.visible = false

func add_player_up_item_card(upgrade: AbilityUpgrade, _current_upgrade: Dictionary):
	var has_card = current_card.has(upgrade.id)
	if !has_card:
		current_card[upgrade.id] = {
			"resource": upgrade
		}
		var card_ins = up_item_card.instantiate()
		card_box.add_child(card_ins)
		card_ins.set_up_item_card(upgrade)
