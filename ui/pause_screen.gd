extends Control

@export var up_item_card: PackedScene
@export_file("*.tscn") var path: String

@onready var animation_player = $AnimationPlayer
@onready var coin = %Coin
@onready var round_num = %RoundNum
@onready var card_box = %CardBox
@onready var player_color = %PlayerColor
@onready var player_halo = %PlayerHalo
@onready var player_p = %PlayerP
@onready var player_name = %PlayerName
@onready var player_weapon = %PlayerWeapon
@onready var resume = %Resume
@onready var option = %Option
@onready var quit = %Quit
@onready var option_menu = $Option
@onready var yes = %Yes
@onready var no = %No

var player: Node
var current_card: Dictionary = {}

var on_menu_selected: bool = false
var on_quit: bool = false
var on_quit_yes: bool = false

var resume_on_touch: bool = false
var option_on_touch: bool = false

var can_pause: bool = true
# 演出/升级等非用户暂停期间为 true：禁止打开暂停菜单，且若已开则强制关闭
var _pause_locked: bool = false

func _ready():
	hide()
	visibility_changed.connect(func():
		if ExtensionHooks.pause_visibility.is_valid():
			ExtensionHooks.notify(ExtensionHooks.pause_visibility, [visible, self])
		else:
			get_tree().paused = visible
		)
	GameEvents.get_player.connect(get_player)
	get_player()
	GameEvents.ability_upgrade_added.connect(add_player_up_item_card)
	GameEvents.round_num_changed.connect(get_round_num)
	GameEvents.player_card_touch.connect(resume_touch_out)
	GameEvents.player_card_touch.connect(option_touch_out)
	GameEvents.round_end.connect(no_can_pause)
	GameEvents.round_start.connect(is_can_pause)
	GameEvents.pause_lock.connect(_on_pause_lock)
	GameEvents.game_over.connect(game_over_no_pause)
	GameEvents.global_time_count.connect(auto_text)
	GameEvents.round_upgrade.connect(hide_pause_screen)
	resume.mouse_entered.connect(resume_mouse_in)
	resume.mouse_exited.connect(resume_mouse_out)
	resume.gui_input.connect(resume_mouse_selected)
	option.mouse_entered.connect(option_mouse_in)
	option.mouse_exited.connect(option_mouse_out)
	option.gui_input.connect(option_mouse_selected)
	quit.mouse_entered.connect(quit_mouse_in)
	quit.mouse_exited.connect(quit_mouse_out)
	quit.gui_input.connect(quit_mouse_selected)
	yes.mouse_entered.connect(yes_mouse_in)
	yes.mouse_exited.connect(yes_mouse_out)
	yes.gui_input.connect(yes_mouse_selected)
	no.mouse_entered.connect(no_mouse_in)
	no.mouse_exited.connect(no_mouse_out)
	no.gui_input.connect(no_mouse_selected)

func _input(event: InputEvent) -> void:
	if  event.is_action_pressed("pause"):
		
		if can_pause == false or _pause_locked:
			return
		
		# LAN：打开由 player._unhandled_input 负责；隐藏时此处直接返回，避免重复 toggle
		if not self.visible and ExtensionHooks.is_lan_session.is_valid() and bool(ExtensionHooks.is_lan_session.call()):
			return
		
		if on_menu_selected == true:
			SoundManager.play_sfx("UISounds2")
			animation_player.play("select_out")
			if option_menu.on_option == true:
				option_menu.out_option_selected()
		else:
			SoundManager.play_sfx("UISounds2")
			SoundManager.bgm_player.volume_db = linear_to_db(1)
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
			hide()
			button_close()
			get_window().set_input_as_handled()

func hide_pause_screen():
	if self.visible == true:
		SoundManager.play_sfx("UISounds2")
		SoundManager.bgm_player.volume_db = linear_to_db(1)
		# 不写鼠标：升级页/商店接管时应由 crosshair(VISIBLE) 持有指针，此处强改会丢失鼠标
		hide()
		button_close()
		get_window().set_input_as_handled()

func auto_text():
	if player_name.size.x > 140:
		var now_font = player_name.get("theme_override_font_sizes/font_size")
		now_font -= 1
		player_name.set("theme_override_font_sizes/font_size", now_font)
	else:
		if GameEvents.global_time_count.is_connected(auto_text):
			GameEvents.global_time_count.disconnect(auto_text)

func game_over_no_pause(_player_dead: bool):
	can_pause = false
	if self.visible == true:
		SoundManager.bgm_player.volume_db = linear_to_db(1)
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
		hide()
		button_close()
		get_window().set_input_as_handled()

func is_can_pause():
	can_pause = true

func no_can_pause():
	can_pause = false

# 演出/升级锁：上锁时关掉已开的暂停菜单，保证 visible 与 get_tree().paused 一致
func _on_pause_lock(locked: bool):
	_pause_locked = locked
	if locked and self.visible:
		# 仅在确实关闭了可见菜单时隐藏指针（Boss 演出需要）；升级场景菜单通常已隐藏，不误伤
		hide_pause_screen()
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func on_menu_selected_false():
	on_menu_selected = false

func button_open():
	resume.mouse_filter = 0
	option.mouse_filter = 0
	quit.mouse_filter = 0

func button_close():
	resume.mouse_filter = 2
	option.mouse_filter = 2
	quit.mouse_filter = 2

func quit_button_open():
	yes.mouse_filter = 0
	no.mouse_filter = 0

func quit_button_close():
	yes.mouse_filter = 2
	no.mouse_filter = 2

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	player_color.color = player.player_card.color
	player_p.texture = LazyTexture.load_uncached(player.player_card.sprite_path)
	player_halo.texture = player.player_card.halo
	player_name.text = player.player_card.name
	player_weapon.text = player.player_card.weapon
	player_weapon.set("theme_override_colors/font_color", player.player_card.color)

func random_player_p():
	var n = randi_range(0,1)
	if n == 0:
		player_p.frame = 0
	else:
		player_p.frame = 2

func show_pause() -> void:
	
	if can_pause == false or _pause_locked:
			return
	
	show()
	SoundManager.play_sfx("ButtonSounds2")
	SoundManager.bgm_player.volume_db = linear_to_db(0.6)
	get_player_coin()
	random_player_p()
	animation_player.play("pause_in")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func get_player_coin():
	coin.text = str(player.stats.coin)

func get_round_num(now_round_num: int):
	round_num.text = str(now_round_num)

func add_player_up_item_card(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	var has_card = current_card.has(upgrade.id)
	if !has_card:
		current_card[upgrade.id] = {
			"resource": upgrade
		}
		var card_ins = up_item_card.instantiate()
		card_box.add_child(card_ins)
		card_ins.set_up_item_card(upgrade)

func resume_mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D10/Node2D9/Resume/AnimationPlayer.play("on_select")

func resume_mouse_out():
	$Node2D10/Node2D9/Resume/AnimationPlayer.play("on_out")

func resume_touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if resume_on_touch == true:
		resume_on_touch = false
		$Node2D10/Node2D9/Resume/AnimationPlayer.play("on_out")

func resume_mouse_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if resume_on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			resume_on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D10/Node2D9/Resume/AnimationPlayer.play("on_select")
		else:
			SoundManager.play_sfx("UISounds2")
			quit_menu_out()
			SoundManager.play_sfx("ButtonSounds")
			hide()
			button_close()
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("UISounds2")
		quit_menu_out()
		SoundManager.play_sfx("ButtonSounds")
		hide()
		button_close()
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func option_mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D10/Node2D9/Option/AnimationPlayer.play("on_select")

func option_mouse_out():
	$Node2D10/Node2D9/Option/AnimationPlayer.play("on_out")

func option_touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if option_on_touch == true:
		option_on_touch = false
		$Node2D10/Node2D9/Option/AnimationPlayer.play("on_out")

func option_mouse_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if option_on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			option_on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D10/Node2D9/Option/AnimationPlayer.play("on_select")
		else:
			SoundManager.play_sfx("UISounds1")
			quit_menu_out()
			on_menu_selected = true
			SoundManager.play_sfx("ButtonSounds")
			button_close()
			animation_player.play("select_anim")
			option_menu.on_option_selected()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("UISounds1")
		quit_menu_out()
		on_menu_selected = true
		SoundManager.play_sfx("ButtonSounds")
		button_close()
		animation_player.play("select_anim")
		option_menu.on_option_selected()

func quit_mouse_in():
	if on_quit == false:
		SoundManager.play_sfx("ButtonSounds2")
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("on_select")

func quit_mouse_out():
	if on_quit == false:
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("on_out")

func quit_mouse_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed and on_quit == false:
		SoundManager.play_sfx("UISounds2")
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("on_select")
		await $Node2D10/Node2D9/Quit/AnimationPlayer.animation_finished
		on_quit = true
		SoundManager.play_sfx("ButtonSounds")
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("selected")
	
	if event.is_action_pressed("shoot") and on_quit == false:
		SoundManager.play_sfx("UISounds2")
		on_quit = true
		SoundManager.play_sfx("ButtonSounds")
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("selected")

func yes_mouse_in():
	if on_quit_yes == false:
		SoundManager.play_sfx("ButtonSounds2")
		$Node2D10/Node2D9/Quit/Node2D/ColorRect/Yes/AnimationPlayer.play("on_select")

func yes_mouse_out():
	if on_quit_yes == false:
		$Node2D10/Node2D9/Quit/Node2D/ColorRect/Yes/AnimationPlayer.play("on_out")

func yes_mouse_selected(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed and on_quit_yes == false:
		if PlayerData.on_test_room == true:
			quit_button_close()
			on_quit_yes = true
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.bgm_fade_out()
			Transition.play_left_start()
			await Transition.left_end_start
			get_tree().paused = false
			GameEvents.change_scene(path,"")
		else:
			if PlayerData.on_endless == false:
				SoundManager.play_sfx("UISounds2")
				SoundManager.bgm_player.volume_db = linear_to_db(1)
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
				hide()
				button_close()
				get_window().set_input_as_handled()
				var player_dead = true
				GameEvents.emit_game_over(player_dead)
			else:
				SoundManager.play_sfx("UISounds2")
				SoundManager.bgm_player.volume_db = linear_to_db(1)
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
				hide()
				button_close()
				get_window().set_input_as_handled()
				var player_dead = false
				GameEvents.emit_game_over(player_dead)
	
	if event.is_action_pressed("shoot") and on_quit_yes == false:
		if PlayerData.on_test_room == true:
			quit_button_close()
			on_quit_yes = true
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.bgm_fade_out()
			Transition.play_left_start()
			await Transition.left_end_start
			get_tree().paused = false
			GameEvents.change_scene(path,"")
		else:
			if PlayerData.on_endless == false:
				
				SoundManager.play_sfx("UISounds2")
				SoundManager.bgm_player.volume_db = linear_to_db(1)
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
				hide()
				button_close()
				get_window().set_input_as_handled()
				var player_dead = true
				GameEvents.emit_game_over(player_dead)
			else:
				SoundManager.play_sfx("UISounds2")
				SoundManager.bgm_player.volume_db = linear_to_db(1)
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
				hide()
				button_close()
				get_window().set_input_as_handled()
				var player_dead = false
				GameEvents.emit_game_over(player_dead)

func no_mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D10/Node2D9/Quit/Node2D/ColorRect/No/AnimationPlayer.play("on_select")

func no_mouse_out():
	$Node2D10/Node2D9/Quit/Node2D/ColorRect/No/AnimationPlayer.play("on_out")

func no_mouse_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed and on_quit_yes == false:
		SoundManager.play_sfx("UISounds2")
		quit_button_close()
		SoundManager.play_sfx("ButtonSounds")
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("no_selected")
	
	if event.is_action_pressed("shoot") and on_quit_yes == false:
		SoundManager.play_sfx("UISounds2")
		quit_button_close()
		SoundManager.play_sfx("ButtonSounds")
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("no_selected")

func on_quit_false():
	on_quit = false

func quit_menu_out():
	if on_quit == true:
		SoundManager.play_sfx("UISounds2")
		on_quit = false
		$Node2D10/Node2D9/Quit/AnimationPlayer.play("no_selected")
