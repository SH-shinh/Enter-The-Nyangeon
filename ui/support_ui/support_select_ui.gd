extends Node2D

signal test_menu_changed

@export var support_card: PackedScene
@export var null_card: SupportCard
@export var test_d: Dictionary
@export var test_menu: bool = false

@onready var support_box: VBoxContainer = %support_box
@onready var ui_anim: AnimationPlayer = $ui_anim
@onready var card_anim: AnimationPlayer = $card_anim
@onready var main_card: PanelContainer = $main_card
@onready var main_name: Label = %MainName
@onready var sprite_2d: Sprite2D = $main_card/Sprite2D
@onready var margin_container: MarginContainer = $MarginContainer

var now_support: SupportCard
var on_select: bool = false

func _ready() -> void:
	main_card.mouse_entered.connect(mouse_in)
	main_card.mouse_exited.connect(mouse_out)
	margin_container.mouse_entered.connect(card_on_select)
	margin_container.mouse_exited.connect(card_out_select)
	GameEvents.support_card_select.connect(get_support_card)
	GameEvents.level_select_in.connect(check_data)
	if test_menu:
		check_data()

func check_data():
	if test_menu == false:
		if SupportData.game_support == null:
			now_support = null_card
		else:
			now_support = SupportData.game_support
			if !SupportData.support_data.has(now_support.support_id):
				now_support = null_card
			
		SupportData.get_card(now_support)
		if SupportData.game_support == null:
			SupportData.game_support = now_support
		update_card()
	else:
		now_support = null_card
		SupportData.get_card(now_support)
		update_card()

func get_support_card(support_card: SupportCard):
	if self.visible == false:
		return
	
	if support_card.support_id == "null":
		if test_menu == true:
			test_menu_changed.emit()
		now_support = support_card
		SupportData.game_support = now_support
		SupportData.get_card(now_support)
		Game.save_playerdata()
		if now_support != null:
			change_card()
	
	if SupportData.support_data.has(support_card.support_id) and test_menu == false:
		now_support = support_card
		SupportData.game_support = now_support
		SupportData.get_card(now_support)
		Game.save_playerdata()
		if now_support != null:
			change_card()
	
	if SupportData.support_pool.has(support_card) and test_menu == true:
		test_menu_changed.emit()
		now_support = support_card
		SupportData.game_support = now_support
		SupportData.get_card(now_support)
		Game.save_playerdata()
		if now_support != null:
			change_card()
	

func card_on_select():
	on_select = true

func card_out_select():
	on_select = false

func mouse_in():
	if on_select == false:
		ui_anim.play("select_anim")
		SoundManager.play_sfx("ButtonSounds2")
		add_cards()

func mouse_out():
	await get_tree().create_timer(0.1).timeout
	if on_select == false:
		ui_anim.play_backwards("select_anim")

func update_card():
	sprite_2d.texture = LazyTexture.load_uncached(now_support.character_sprite_path)
	main_name.text = now_support.support_name2

func change_card():
	card_anim.play("change_card")
	await card_anim.animation_finished
	update_card()
	card_anim.play_backwards("change_card")

func add_null_card():
	var ins = support_card.instantiate()
	ins.shop_card = null_card
	support_box.add_child(ins)
	ins.reveal()

func clear_box():
	var cards = support_box.get_children()
	if !cards.is_empty():
		for i in cards.size():
			cards[i].queue_free()

func add_cards():
	clear_box()
	add_null_card()
	if !SupportData.support_data.is_empty() and test_menu == false:
		var group = SupportData.support_data.values()
		for i in group.size():
			var ins = support_card.instantiate()
			ins.shop_card = group[i]["resource"]
			support_box.add_child(ins)
			ins.reveal()
	
	if !SupportData.support_pool.is_empty() and test_menu == true:
		for i in SupportData.support_pool.size():
			var ins = support_card.instantiate()
			ins.shop_card = SupportData.support_pool[i]
			support_box.add_child(ins)
			ins.reveal()
	

func _on_main_card_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		ui_anim.play("select_anim")
		SoundManager.play_sfx("ButtonSounds2")
		add_cards()
