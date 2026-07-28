extends Node

signal summoned_buff_added(summoned_buff: Buff, current_buff: Dictionary)

@export var buff_poll: Array[Buff]
@export var buff_card: PackedScene

var current_buff = {}
var body
var is_idle: int = 0

func _ready():
	body = get_parent()

func add_buff_card(summoned_buff: Buff, buff_node: Node):
	var buff_card_instance = PoolManager.get_buff_pool()
	if buff_card_instance == null:
		buff_card_instance = buff_card.instantiate()
		body.buff_box.add_child(buff_card_instance)
	else:
		buff_card_instance.reparent(body.buff_box)
	buff_card_instance.set_buff_card(summoned_buff)
	buff_card_instance.get_player_buff(buff_node)
	buff_card_instance.active_state()

func emit_summoned_buff_added(summoned_buff: Buff, current_buff: Dictionary):
	summoned_buff_added.emit(summoned_buff, current_buff)

func apply_buff(summoned_buff: Buff, value: Array):
	if is_idle == 1:
		return
	
	var has_buff = current_buff.has(summoned_buff.id)
	if !has_buff:
		
		var scene_path = "res://scenes/summoned_buff/" + str(summoned_buff.id) + ".tscn"
		var scene = load(scene_path)
		var add_buff = scene.instantiate()
		add_buff.buff_layer = value[0]
		add_buff.buff_value = value[1]
		add_buff.buff_erase_timer = value[2]
		body.add_child(add_buff)
		add_buff_card(summoned_buff, add_buff)
		add_buff.buff_time_out.connect(remove_buff)
		
		current_buff[summoned_buff.id] = {
			"resource": summoned_buff,
			"buff": add_buff,
			"quantity": 1
		}
		
	else:
		current_buff[summoned_buff.id]["quantity"] += 1
		
	emit_summoned_buff_added(summoned_buff, current_buff)

func remove_buff(summoned_buff: Buff):
	
	if current_buff.has(summoned_buff.id) and current_buff[summoned_buff.id]["buff"] != null:
		current_buff[summoned_buff.id]["buff"].clear_buff()
	current_buff.erase(summoned_buff.id)
	
