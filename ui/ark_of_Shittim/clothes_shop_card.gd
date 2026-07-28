extends PanelContainer

signal change_clothes(send_card: ClothesCard)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var item_icon: TextureRect = $Node2D/ItemIcon

var on_select: bool = false

var self_card: ClothesCard
var ins = preload("res://resources/clothes/Plana/normal.tres")
func _ready() -> void:
	gui_input.connect(select_button)

func get_card(cloth_card: ClothesCard):
	self_card = cloth_card
	item_icon.texture = cloth_card.icon_2

func open_button():
	self.mouse_filter = 0

func close_button():
	self.mouse_filter = 2

func select_button(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		change_character_clothes()
	
	if event.is_action_pressed("shoot"):
		change_character_clothes()

func button_select():
	if on_select == false:
		close_button()
		on_select = true
		animation_player.play("select_anim")

func change_character_clothes():
	if self_card != null:
		SoundManager.play_sfx("ButtonSounds")
		button_select()
		change_clothes.emit(self_card)

func out_button():
	if on_select == true:
		open_button()
		on_select = false
		animation_player.play_backwards("select_anim")
