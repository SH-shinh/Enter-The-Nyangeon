extends PanelContainer

@export var shop_card: SupportCard

@onready var support_sprite: Sprite2D = %support_sprite
@onready var main_name: Label = %MainName
@onready var card_anim: AnimationPlayer = $AnimationPlayer

var on_select: bool = false
var _revealed_path: String = ""

func _ready() -> void:
	mouse_entered.connect(mouse_in)
	mouse_exited.connect(mouse_out)
	gui_input.connect(add_card)
	GameEvents.support_card_select.connect(check_card)
	get_card()

func get_card():
	if support_sprite != null:
		main_name.text = shop_card.support_name2
	else:
		main_name.text = "NULL"


# 立绘大图按需加载/释放（列表可见性由 support_shop 调用）；幂等
func reveal() -> void:
	if support_sprite == null or shop_card == null:
		return
	var p := shop_card.character_sprite_path
	if _revealed_path == p and support_sprite.texture != null:
		return
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
	support_sprite.texture = LazyTexture.acquire(p)
	_revealed_path = p


func conceal() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""
	if support_sprite != null:
		support_sprite.texture = null


func _exit_tree() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""

func check_card(s_card: SupportCard):
	if s_card != shop_card and on_select == true:
		mouse_open()

func mouse_open():
	mouse_filter = 0
	if on_select == true:
		card_anim.play_backwards("select_anim")
		on_select = false

func mouse_close():
	mouse_filter = 2

func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	card_anim.play("select_anim")

func mouse_out():
	if on_select == false:
		card_anim.play_backwards("select_anim")

func emit_support_card():
	on_select = true
	GameEvents.emit_support_card_select(shop_card)
	mouse_close()

func add_card(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_select == false:
			SoundManager.play_sfx("ButtonSounds")
			card_anim.play("select_anim")
			emit_support_card()
	
	if event.is_action_pressed("shoot"):
		if on_select == false:
			SoundManager.play_sfx("ButtonSounds")
			emit_support_card()
