extends Node2D

@export var id_name: String
@export var sprite_node: Node
@onready var card_box: GridContainer = %CardBox
@onready var button_card: PackedScene = preload("res://ui/ark_of_Shittim/clothes_shop_card.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var change_shop: PanelContainer = $ChangeShop
@onready var color_rect: ColorRect = $ChangeShop/Node2D/ColorRect

var is_open: bool = false
var button_group: Array

func _ready() -> void:
	change_shop.gui_input.connect(select_button)

func select_button(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		open_menu()
	
	if event.is_action_pressed("shoot"):
		open_menu()

func open_menu():
	SoundManager.play_sfx("ButtonSounds")
	if is_open == false:
		is_open = true
		animation_player.play("select_anim")
		add_card()
	else:
		close_menu()

func close_button():
	color_rect.mouse_filter = 0

func open_button():
	color_rect.mouse_filter = 2

func close_menu():
	change_shop.mouse_filter = 2
	animation_player.play_backwards("select_anim")
	button_group.clear()
	for i in card_box.get_children():
		if i.change_clothes.is_connected(change_sprite_clothes):
			i.change_clothes.disconnect(change_sprite_clothes)
		i.queue_free()
	await animation_player.animation_finished
	is_open = false
	change_shop.mouse_filter = 0

func add_card():
	if PlayerData.clothes_group.has(id_name):
		for i in PlayerData.clothes_group[id_name].size():
			var ins = button_card.instantiate()
			var card_load = load("res://resources/clothes/" + id_name + "/" + PlayerData.clothes_group[id_name][i] + ".tres")
			card_box.add_child(ins)
			ins.get_card(card_load)
			ins.change_clothes.connect(change_sprite_clothes)
			if PlayerData.now_clothes[id_name] == PlayerData.clothes_group[id_name][i]:
				ins.button_select()
			button_group.push_back(ins)

func change_sprite_clothes(self_card: ClothesCard):
	PlayerData.now_clothes[id_name] = self_card.id
	for i in button_group.size():
		if button_group[i].self_card.id != PlayerData.now_clothes[id_name]:
			button_group[i].out_button()
	sprite_node.change_clothes(self_card)
	Game.save_playerdata()
