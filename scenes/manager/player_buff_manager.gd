extends Node


@export var buff_poll: Array[Buff]
@export var buff_card: PackedScene

var current_buff = {}
var player

func _ready():
	GameEvents.get_player.connect(get_player)
	get_player()

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func add_buff_card(player_buff: Buff, buff_node: Node):
	if player == null:
		return
	var buff_card_instance = PoolManager.get_buff_pool()
	if buff_card_instance == null:
		buff_card_instance = buff_card.instantiate()
		player.game_ui.buff_box.add_child(buff_card_instance)
	else:
		buff_card_instance.reparent(player.game_ui.buff_box)
	buff_card_instance.set_buff_card(player_buff)
	buff_card_instance.get_player_buff(buff_node)
	buff_card_instance.active_state()

func apply_buff(player_buff: Buff, value: Array):
	if player == null:
		return
	var has_buff = current_buff.has(player_buff.id)
	if !has_buff:
		
		var scene_path = "res://scenes/player_buff/" + str(player_buff.id) + ".tscn"
		var scene = load(scene_path)
		var add_buff = scene.instantiate()
		add_buff.buff_layer = value[0] * player.stats.buff_layer_mult
		add_buff.buff_value = value[1]
		add_buff.buff_erase_timer = value[2]
		player.add_child(add_buff)
		add_buff_card(player_buff, add_buff)
		add_buff.buff_time_out.connect(remove_buff)
		
		current_buff[player_buff.id] = {
			"resource": player_buff,
			"buff": add_buff,
			"quantity": 1
		}
		
	else:
		if current_buff[player_buff.id]["quantity"] < value[0]:
			current_buff[player_buff.id]["quantity"] += 1
		
	GameEvents.emit_player_buff_added(player_buff, current_buff)

func remove_buff(player_buff: Buff):
	if player == null:
		return
	if current_buff.has(player_buff.id) and current_buff[player_buff.id]["buff"] != null:
		current_buff[player_buff.id]["buff"].clear_buff()
	current_buff.erase(player_buff.id)
	GameEvents.emit_player_buff_remove(player_buff.id)
