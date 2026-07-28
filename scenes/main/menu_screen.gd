extends CanvasLayer

signal player_card_clear_done

@export var bgm_first_cut: AudioStream
@export var bgm_loop: AudioStream

@onready var test_room: PanelContainer = %TestRoom
@onready var new_game = %NewGame
@onready var option = %Option
@onready var quit = %Quit
@onready var menu_anim = $AnimationPlayer
@onready var select_player = $SelectPlayer/AnimationPlayer
@onready var player_card_box = $SelectPlayer/Node2D2/MarginContainer/PlayerCardBox
@onready var gdd: PanelContainer = $SelectPlayer/Node2D/SocietyCardBox/ScrollContainer/VBoxContainer/GDD
@onready var society_card_box = $SelectPlayer/Node2D/SocietyCardBox/ScrollContainer/VBoxContainer
@onready var option_menu = $OptionMenu
@onready var shop_menu: Node2D = $Node2D6/ShopMenu
@onready var version: Label = %version
@onready var scoreboard: Control = $scoreboard

var on_select_anim: bool = false
var on_select_player: bool = false
var on_select_level: bool = false

var test_room_on_touch: bool = false
var new_game_on_touch: bool = false
var option_on_touch: bool = false
var quit_on_touch: bool = false

var society_card_group: Array[Node] = []

func _ready():
	SoundManager.cut_finish.connect(bgm_loop_play)
	SoundManager.play_bgm_cut(bgm_first_cut)
	test_room.mouse_entered.connect(test_room_select)
	test_room.mouse_exited.connect(test_room_out)
	test_room.gui_input.connect(on_test_room)
	new_game.mouse_entered.connect(new_game_select)
	new_game.mouse_exited.connect(new_game_out)
	new_game.gui_input.connect(on_new_game)
	option.mouse_entered.connect(option_select)
	option.mouse_exited.connect(option_out)
	option.gui_input.connect(on_option)
	quit.mouse_entered.connect(quit_select)
	quit.mouse_exited.connect(quit_out)
	quit.gui_input.connect(on_quit)
	GameEvents.society_card_selected.connect(society_card_filter)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameEvents.player_card_selected.connect(on_level_select)
	GameEvents.level_select_out.connect(out_level_select)
	GameEvents.player_card_touch.connect(test_room_touch_out)
	GameEvents.player_card_touch.connect(new_game_touch_out)
	GameEvents.player_card_touch.connect(quit_touch_out)
	GameEvents.player_card_touch.connect(option_touch_out)
	version.text = Game.version_number
	SupportData.reset_game_support()

func on_level_select():
	on_select_level = true

func out_level_select():
	await get_tree().create_timer(0.1).timeout
	on_select_level = false

func _unhandled_input(event:InputEvent ) -> void:
	if on_select_anim == true:
		if event.is_action_pressed("pause"):
			
			if on_select_level == false:
				SoundManager.play_sfx("UISounds2")
				menu_anim.play("out_anim")
			
			if on_select_player == true and on_select_level == false:
				SoundManager.play_sfx("UISounds2")
				select_player.play("out_player")
				await select_player.animation_finished
				change_player_card()
				society_card_group.clear()
				var cards = society_card_box.get_children()
				for i in cards.size():
					cards[i].out_select_card()
			if option_menu.on_option == true:
				option_menu.out_option_selected()

func select_close():
	on_select_anim = false

func select_copen():
	on_select_anim = true

func on_select_player_true():
	on_select_player = true

func on_select_player_false():
	on_select_player = false

func button_open():
	test_room.mouse_filter = 0
	new_game.mouse_filter = 0
	option.mouse_filter = 0
	quit.mouse_filter = 0
	shop_menu.button_open.emit()

func button_close():
	test_room.mouse_filter = 2
	new_game.mouse_filter = 2
	option.mouse_filter = 2
	quit.mouse_filter = 2
	shop_menu.button_close.emit()

func bgm_loop_play():
	SoundManager.play_bgm(bgm_loop)

func test_room_select():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D5/TestRoom/AnimationPlayer.play("on_select")

func test_room_out():
	$Node2D5/TestRoom/AnimationPlayer.play_backwards("on_select")

func on_test_room(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		if new_game_on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			new_game_on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D5/TestRoom/AnimationPlayer.play("on_select")
		else:
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.play_sfx("UISounds1")
			SoundManager.bgm_fade_out()
			Transition.play_left_start()
			await Transition.left_end_start
			GameEvents.change_scene("res://scenes/main/test_room.tscn","res://scenes/player/momoi/momoi.tscn")
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		SoundManager.play_sfx("UISounds1")
		SoundManager.bgm_fade_out()
		Transition.play_left_start()
		await Transition.left_end_start
		GameEvents.change_scene("res://scenes/main/test_room.tscn","res://scenes/player/momoi/momoi.tscn")

func test_room_touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if test_room_on_touch == true:
		test_room_on_touch = false
		$Node2D5/TestRoom/AnimationPlayer.play_backwards("on_select")

func new_game_select():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D5/NewGame/AnimationPlayer.play("on_select")

func new_game_out():
	$Node2D5/NewGame/AnimationPlayer.play("on_out")

func new_game_touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if new_game_on_touch == true:
		new_game_on_touch = false
		$Node2D5/NewGame/AnimationPlayer.play("on_out")

func on_new_game(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if new_game_on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			new_game_on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D5/NewGame/AnimationPlayer.play("on_select")
		else:
			GameEvents.emit_check_data()
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.play_sfx("UISounds1")
			button_close()
			menu_anim.play("select_anim")
			select_player.play("select_player")
			await select_player.animation_finished
			gdd.on_select_handle()
	
	
	if event.is_action_pressed("shoot"):
		GameEvents.emit_check_data()
		SoundManager.play_sfx("ButtonSounds")
		SoundManager.play_sfx("UISounds1")
		button_close()
		menu_anim.play("select_anim")
		select_player.play("select_player")
		await select_player.animation_finished
		gdd.on_select_handle()

func option_select():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D5/Option/AnimationPlayer.play("on_select")

func option_out():
	$Node2D5/Option/AnimationPlayer.play("on_out")

func option_touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if option_on_touch == true:
		option_on_touch = false
		$Node2D5/Option/AnimationPlayer.play("on_out")

func on_option(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if option_on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			option_on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D5/Option/AnimationPlayer.play("on_select")
		else:
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.play_sfx("UISounds1")
			button_close()
			menu_anim.play("select_anim")
			option_menu.on_option_selected()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		SoundManager.play_sfx("UISounds1")
		button_close()
		menu_anim.play("select_anim")
		option_menu.on_option_selected()

func quit_select():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D5/Quit/AnimationPlayer.play("on_select")

func quit_out():
	$Node2D5/Quit/AnimationPlayer.play("on_out")

func quit_touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if quit_on_touch == true:
		quit_on_touch = false
		$Node2D5/Quit/AnimationPlayer.play("on_out")

func on_quit(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if quit_on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			quit_on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D5/Quit/AnimationPlayer.play("on_select")
		else:
			SoundManager.play_sfx("ButtonSounds")
			button_close()
			get_tree().quit()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		button_close()
		get_tree().quit()

func society_card_filter(society_card: Node):
	society_card_group.push_back(society_card)
	if society_card_group.size() > 1:
		society_card_group[0].out_select_card()
		society_card_group.remove_at(0)
	select_player.play("change_player_card")
	await player_card_clear_done
	
	for i in 4:
		if society_card.card_group[i] != "":
			var card_ins = load(society_card.card_group[i]).instantiate()
			if PlayerData.character.has(card_ins.player_card.id):
				player_card_box.add_child(card_ins)
				await get_tree().create_timer(0.07).timeout

func change_player_card():
	var cards = player_card_box.get_children()
	for i in cards.size():
		cards[i].queue_free()
	player_card_clear_done.emit()

func _on_score_button_pressed() -> void:
	SoundManager.play_sfx("UISounds2")
	scoreboard.show_scoreboard()

func _on_score_button_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_score_button_pressed()
