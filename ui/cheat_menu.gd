extends CanvasLayer

@export var can_cheat: bool = false
@export var upgrade_manager: Node
@export var round_timer: Node

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var box: GridContainer = $ScrollContainer/GridContainer
@onready var button: Button = $Button

var test_card = preload("res://ui/test_item_card.tscn")
var upgrades_pool_c: Array[AbilityUpgrade] = []

var player: Node

func _ready() -> void:
	add_card()

func _unhandled_input(event):
	if event.is_action_pressed("cheat_menu"):
		if can_cheat == true:
			if self.visible == true:
				self.visible = false
				Engine.time_scale = 1
			else:
				self.visible = true
				Engine.time_scale = 0.01

func add_card():
	upgrades_pool_c = upgrade_manager.upgrade_pool.duplicate()
	for i in upgrades_pool_c.size():
		var ins = test_card.instantiate()
		box.add_child(ins)
		ins.upgrade_manager = upgrade_manager
		ins.get_card(upgrades_pool_c[i])

func _on_button_pressed() -> void:
	round_timer.timer.stop()
	round_timer.round_time = 0
	round_timer._on_timer_timeout()


func _on_button_2_pressed() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("Player")
	player.stats.coin += 1000


func _on_button_3_pressed() -> void:
	round_timer.now_round_num += 1
