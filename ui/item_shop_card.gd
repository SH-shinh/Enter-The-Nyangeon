extends PanelContainer

@export var shop_card: ClothesCard

@onready var user_name_2: Label = %UserName2
@onready var cost: Label = %Cost
@onready var name_1: Label = %Name1
@onready var name_2: Label = %Name2
@onready var user_name_1: Label = %UserName1
@onready var item_1: Sprite2D = %Item1
@onready var item_2: Sprite2D = %Item2
@onready var yes: PanelContainer = %Yes
@onready var no: PanelContainer = %No

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var yes_anim: AnimationPlayer = $Node2D3/Panel/TextureRect/Yes/YesAnim
@onready var no_anim: AnimationPlayer = $Node2D3/Panel/TextureRect/No/Node2D/NoAnim

var is_confirm: bool = false

func _ready() -> void:
	mouse_entered.connect(mouse_select)
	mouse_exited.connect(mouse_out)
	gui_input.connect(confirm_open)
	yes.mouse_entered.connect(yes_select)
	yes.mouse_exited.connect(yes_out)
	yes.gui_input.connect(yes_deal)
	no.mouse_entered.connect(no_select)
	no.mouse_exited.connect(no_out)
	no.gui_input.connect(no_deal)
	get_card()

func open_main_button():
	self.mouse_filter = 0

func close_main_button():
	self.mouse_filter = 2

func open_button():
	yes.mouse_filter = 0
	no.mouse_filter = 0

func close_button():
	yes.mouse_filter = 2
	no.mouse_filter = 2

func get_card():
	if shop_card != null:
		name_1.text = shop_card.name_1
		name_2.text = shop_card.name_2
		item_1.texture = shop_card.icon_2
		item_2.texture = shop_card.icon_2
		user_name_1.text = shop_card.user_name
		user_name_2.text = shop_card.user_name
		cost.text = str(shop_card.cost)

func check_data():
	if shop_card != null:
		var group: Array = PlayerData.clothes_group.get(shop_card.id_name, [])
		if group.has(shop_card.id):
			close_main_button()
			close_button()
			animation_player_2.play("deal_anim")

func mouse_select():
	if is_confirm == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("select_anim")
		animation_player_2.play("select_anim")

func mouse_out():
	if is_confirm == false:
		animation_player.play("RESET")
		animation_player_2.play_backwards("select_anim")

func yes_select():
	SoundManager.play_sfx("ButtonSounds2")
	yes_anim.play("select_anim")

func yes_out():
	yes_anim.play_backwards("select_anim")

func yes_deal(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds2")
		close_button()
		yes_anim.play("select_anim")
		await yes_anim.animation_finished
		if shop_card.cost <= PlayerData.player_pyroxenes:
			add_item()
			PlayerData.player_pyroxenes -= shop_card.cost
			SoundManager.play_sfx("CoinSounds")
			animation_player_2.play_backwards("confirm_anim")
			await animation_player_2.animation_finished
			animation_player.play("RESET")
			animation_player_2.play_backwards("select_anim")
			await animation_player_2.animation_finished
			animation_player_2.play("deal_anim")
		else:
			GameEvents.emit_pyroxenes_not_enough("Arona")
			yes_anim.play_backwards("select_anim")
			open_button()
	
	if event.is_action_pressed("shoot"):
		if shop_card.cost <= PlayerData.player_pyroxenes:
			add_item()
			PlayerData.player_pyroxenes -= shop_card.cost
			SoundManager.play_sfx("CoinSounds")
			close_button()
			animation_player_2.play_backwards("confirm_anim")
			await animation_player_2.animation_finished
			animation_player.play("RESET")
			animation_player_2.play_backwards("select_anim")
			await animation_player_2.animation_finished
			animation_player_2.play("deal_anim")
		else:
			GameEvents.emit_pyroxenes_not_enough("Arona")

func add_item():
	var group: Array = PlayerData.clothes_group.get(shop_card.id_name, [])
	if !group.has(shop_card.id):
		group.push_back(shop_card.id)
		PlayerData.clothes_group[shop_card.id_name] = group
		Game.save_playerdata()

func no_deal(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds2")
		close_button()
		no_anim.play("select_anim")
		await no_anim.animation_finished
		confirm_close()
		no_anim.play_backwards("select_anim")
	
	if event.is_action_pressed("shoot"):
		confirm_close()
		

func no_select():
	SoundManager.play_sfx("ButtonSounds2")
	no_anim.play("select_anim")

func no_out():
	no_anim.play_backwards("select_anim")

func confirm_open(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		if is_confirm == false:
			is_confirm = true
			SoundManager.play_sfx("ButtonSounds2")
			animation_player.play("select_anim")
			animation_player_2.play("select_anim")
			close_main_button()
			await animation_player_2.animation_finished
			animation_player_2.play("confirm_anim")
			await animation_player_2.animation_finished
			open_button()
	
	if event.is_action_pressed("shoot"):
		is_confirm = true
		SoundManager.play_sfx("ButtonSounds")
		animation_player_2.play("confirm_anim")
		close_main_button()
		await animation_player_2.animation_finished
		open_button()

func confirm_close():
	SoundManager.play_sfx("UISounds2")
	animation_player_2.play_backwards("confirm_anim")
	close_button()
	await animation_player_2.animation_finished
	is_confirm = false
	open_main_button()
