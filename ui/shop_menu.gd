extends Node2D

signal shop_open
signal button_open
signal button_close

@export var shop_card_group: Array[CharacterCard]
@export var shop_item_group: Array[ClothesCard]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var shop_button: PanelContainer = $ShopButton
@onready var wealth: Label = %Wealth
@onready var arona: Node2D = $Node2D/Node2D/ColorRect/Arona
@onready var plana: Node2D = $Node2D/Node2D/ColorRect/Plana
@onready var shop_anim: AnimationPlayer = $Node2D/shop_anim
@onready var change_shop: PanelContainer = $Node2D/Node2D/ColorRect/Arona/ChangeShop
@onready var change_shop_2: PanelContainer = $Node2D/Node2D/ColorRect/Plana/ChangeShop2
@onready var card_box: GridContainer = %CardBox
@onready var card_box_2: GridContainer = %CardBox2
@onready var card_ins: PackedScene = preload("res://ui/character_shop_card.tscn")
@onready var card_ins_2: PackedScene = preload("res://ui/item_shop_card.tscn")
@onready var shop_tag_button_1: PanelContainer = $Node2D/Node2D2/Shop/Node2D/ShopTagButton1
@onready var shop_tag_button_2: PanelContainer = $Node2D/Node2D2/Shop/Node2D/ShopTagButton2

var shop_is_open: bool = false
var shop_show: bool = false
var shop_open_end: bool = false

var shop_type: int = 0

func _ready() -> void:
	shop_button.mouse_entered.connect(mouse_select)
	shop_button.mouse_exited.connect(mouse_out)
	shop_button.gui_input.connect(shop_menu_open)
	change_shop.gui_input.connect(change_shop_select)
	change_shop_2.gui_input.connect(change_shop_select)
	
	shop_tag_button_1.button_select.connect(shop_tag_1_open)
	shop_tag_button_2.button_select.connect(shop_tag_2_open)
	
	button_open.connect(shop_button_open)
	button_close.connect(shop_button_close)
	PlayerData.pyroxenes_changed.connect(update_wealth)
	update_wealth()
	add_charavter_card()
	add_item_card()

func emit_shop_open():
	shop_open.emit()

func update_wealth():
	wealth.text = str(PlayerData.player_pyroxenes)

func add_charavter_card():
	for i in shop_card_group.size():
		var ins = card_ins.instantiate()
		card_box.add_child(ins)
		ins.shop_card = shop_card_group[i]
		ins.get_card()
		ins.check_data()

func add_item_card():
	for i in shop_item_group.size():
		var ins = card_ins_2.instantiate()
		card_box_2.add_child(ins)
		ins.shop_card = shop_item_group[i]
		ins.get_card()
		ins.check_data()

func shop_button_open():
	shop_button.mouse_filter = 0

func shop_button_close():
	shop_button.mouse_filter = 2

func shop_is_show():
	shop_show = true

func mouse_select():
	if shop_is_open == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("select_anim")

func mouse_out():
	if shop_is_open == false:
		animation_player.play_backwards("select_anim")

func _unhandled_input(event:InputEvent ) -> void:
	if shop_open_end == true:
		if event.is_action_pressed("pause"):
			shop_open_end = false
			animation_player.play_backwards("shop_open")
			if shop_type == 0:
				shop_anim.play_backwards("arona_shop")
			elif shop_type == 1:
				shop_anim.play_backwards("plana_shop")
			await animation_player.animation_finished
			shop_type = 0
			animation_player.play_backwards("select_anim")
			await animation_player.animation_finished
			shop_is_open = false
			shop_show = false

func shop_menu_open(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if shop_is_open == false and shop_show == false:
			SoundManager.play_sfx("ButtonSounds2")
			animation_player.play("select_anim")
		if shop_is_open == false and shop_show == true:
			SoundManager.play_sfx("ButtonSounds")
			if animation_player.is_playing():
				await animation_player.animation_finished
			animation_player.play("shop_open")
			shop_is_open = true
			await get_tree().create_timer(0.2).timeout
			shop_anim.play("arona_shop")
			shop_tag_button_1.open_shop_menu()
			await animation_player.animation_finished
			shop_open_end = true
			arona.worl_in_voice()
	
	if event.is_action_pressed("shoot"):
		if shop_is_open == false and shop_show == true:
			SoundManager.play_sfx("ButtonSounds")
			if animation_player.is_playing():
				await animation_player.animation_finished
			animation_player.play("shop_open")
			shop_is_open = true
			await get_tree().create_timer(0.2).timeout
			shop_anim.play("arona_shop")
			shop_tag_button_1.open_shop_menu()
			await animation_player.animation_finished
			shop_open_end = true
			arona.worl_in_voice()
	

func change_shop_select(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		change_shop.mouse_filter = 2
		shop_open_end = false
		if shop_type == 0:
			shop_anim.play_backwards("arona_shop")
			await shop_anim.animation_finished
			shop_anim.play("plana_shop")
			await shop_anim.animation_finished
			plana.worl_in_voice()
			shop_type = 1
			change_shop.mouse_filter = 0
			shop_open_end = true
		elif shop_type == 1:
			shop_anim.play_backwards("plana_shop")
			await shop_anim.animation_finished
			shop_anim.play("arona_shop")
			await shop_anim.animation_finished
			arona.worl_in_voice()
			shop_type = 0
			change_shop.mouse_filter = 0
			shop_open_end = true
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		change_shop.mouse_filter = 2
		shop_open_end = false
		if shop_type == 0:
			shop_anim.play_backwards("arona_shop")
			await shop_anim.animation_finished
			shop_anim.play("plana_shop")
			await shop_anim.animation_finished
			plana.worl_in_voice()
			shop_type = 1
			change_shop.mouse_filter = 0
			shop_open_end = true
		elif shop_type == 1:
			shop_anim.play_backwards("plana_shop")
			await shop_anim.animation_finished
			shop_anim.play("arona_shop")
			await shop_anim.animation_finished
			arona.worl_in_voice()
			shop_type = 0
			change_shop.mouse_filter = 0
			shop_open_end = true
			

func shop_tag_1_open():
	shop_tag_2_close()
	$Node2D/Node2D2/Shop/ItemList1/ItemList1Anim.play("select_anim")

func shop_tag_1_close():
	$Node2D/Node2D2/Shop/ItemList1/ItemList1Anim.play("RESET")
	shop_tag_button_1.close_shop_menu()

func shop_tag_2_open():
	shop_tag_1_close()
	$Node2D/Node2D2/Shop/ItemList2/ItemList2Anim.play("select_anim")

func shop_tag_2_close():
	$Node2D/Node2D2/Shop/ItemList2/ItemList2Anim.play("RESET")
	shop_tag_button_2.close_shop_menu()
