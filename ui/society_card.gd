extends PanelContainer

@export_file("*.tscn") var player_card_1: String
@export_file("*.tscn") var player_card_2: String
@export_file("*.tscn") var player_card_3: String
@export_file("*.tscn") var player_card_4: String

@export var group_id: String

@onready var card_anim = $AnimationPlayer

var on_select: bool = false

@onready var card_group: Array =[player_card_1, player_card_2, player_card_3, player_card_4]

func _ready():
	mouse_entered.connect(mouse_select_anim)
	mouse_exited.connect(mouse_out_anim)
	gui_input.connect(on_select_card)
	check_group()
	PlayerData.pyroxenes_changed.connect(check_group)
	GameEvents.check_data.connect(check_group)

func check_group():
	if PlayerData.group.has(group_id):
		self.visible = true
	else:
		self.visible = false

func open_card():
	mouse_filter = 0

func close_card():
	mouse_filter = 2

func mouse_select_anim():
	if on_select == false:
		SoundManager.play_sfx("ButtonSounds2")
		card_anim.play("select_anim")

func mouse_out_anim():
	if on_select == false:
		card_anim.play("out_anim")

func on_select_card(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed and on_select == false:
		SoundManager.play_sfx("ButtonSounds")
		on_select_handle()
	
	if event.is_action_pressed("shoot") and on_select == false:
		SoundManager.play_sfx("ButtonSounds")
		on_select_handle()

func on_select_handle():
	on_select = true
	card_anim.play("on_select_anim")
	GameEvents.emit_society_card_selected(self)
	close_card()
	#await card_anim.animation_finished
	#close_card.call_deferred()

func out_select_card():
	if on_select == true:
		on_select = false
		card_anim.play("out_select_anim")
		await get_tree().create_timer(0.3).timeout
		open_card()
