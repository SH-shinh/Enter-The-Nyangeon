extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var game_option_anim = $Node2D2/AnimationPlayer
@onready var controls_option_player = $Controls/AnimationPlayer

@onready var game = $Node2D/Game
@onready var controls = $Node2D/Controls
@onready var full_screen = $Node2D2/Graphics/FullScreen
@onready var shake = $Node2D2/Graphics/Shake
@onready var v_sync = $"Node2D2/Graphics/V-Sync"


var on_option: bool = false

var botton_group: Array

var on_game: bool = false
var on_controls: bool = false

func _ready():
	setting_status()
	game.mouse_entered.connect(mouse_on_game)
	game.mouse_exited.connect(mouse_out_game)
	game.gui_input.connect(mouse_selected_game)
	controls.mouse_entered.connect(mouse_on_controls)
	controls.mouse_exited.connect(mouse_out_controls)
	controls.gui_input.connect(mouse_selected_controls)
	full_screen.mouse_entered.connect(mouse_on_full_screen)
	full_screen.mouse_exited.connect(mouse_out_full_screen)
	full_screen.gui_input.connect(mouse_selected_full_screen)
	shake.mouse_entered.connect(mouse_on_shake)
	shake.mouse_exited.connect(mouse_out_shake)
	shake.gui_input.connect(mouse_selected_shake)
	v_sync.mouse_entered.connect(mouse_on_vs)
	v_sync.mouse_exited.connect(mouse_out_vs)
	v_sync.gui_input.connect(mouse_selected_vs)

func button_open():
	game.mouse_filter = 0
	controls.mouse_filter = 0

func button_close():
	game.mouse_filter = 2
	controls.mouse_filter = 2

func on_option_selected():
	animation_player.play("option_in")
	on_option = true

func out_option_selected():
	SoundManager.play_sfx("UISounds2")
	animation_player.play("option_out")
	on_option = false

func botton_out_anim():
	if on_game == true:
		on_game = false
		$Node2D/Game/AnimationPlayer.play("on_out")
		game_option_anim.play("game_option_out")
	if on_controls == true:
		on_controls = false
		$Node2D/Controls/AnimationPlayer.play("on_out")
		controls_option_player.play("conrtols_out")

func mouse_on_game():
	if on_game == false:
		SoundManager.play_sfx("ButtonSounds2")
		$Node2D/Game/AnimationPlayer.play("on_select")

func mouse_out_game():
	if on_game == false:
		$Node2D/Game/AnimationPlayer.play("on_out")

func mouse_selected_game(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		botton_out_anim()
		on_game = true
		$Node2D/Game/AnimationPlayer.play("selected")
		game_option_anim.play("game_option_in")
	
	if event.is_action_pressed("shoot") and on_game == false:
		SoundManager.play_sfx("ButtonSounds")
		botton_out_anim()
		on_game = true
		$Node2D/Game/AnimationPlayer.play("selected")
		game_option_anim.play("game_option_in")

func mouse_on_controls():
	if on_controls == false:
		SoundManager.play_sfx("ButtonSounds2")
		$Node2D/Controls/AnimationPlayer.play("on_select")

func mouse_out_controls():
	if on_controls == false:
		$Node2D/Controls/AnimationPlayer.play("on_out")

func mouse_selected_controls(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		botton_out_anim()
		on_controls = true
		$Node2D/Controls/AnimationPlayer.play("selected")
		controls_option_player.play("controls_in")
	
	if event.is_action_pressed("shoot") and on_controls == false:
		SoundManager.play_sfx("ButtonSounds")
		botton_out_anim()
		on_controls = true
		$Node2D/Controls/AnimationPlayer.play("selected")
		controls_option_player.play("controls_in")

func mouse_on_full_screen():
	if Game.on_full_screen == false:
		$Node2D2/Graphics/FullScreen/AnimationPlayer.play("full_on")
	else:
		$Node2D2/Graphics/FullScreen/AnimationPlayer.play("selected_out")

func mouse_out_full_screen():
	if Game.on_full_screen == false:
		$Node2D2/Graphics/FullScreen/AnimationPlayer.play("full_out")
	else:
		$Node2D2/Graphics/FullScreen/AnimationPlayer.play("selected")

func mouse_selected_full_screen(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.on_full_screen == false:
			Game.on_full_screen = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			$Node2D2/Graphics/FullScreen/AnimationPlayer.play("selected")
			Game.save_config()
		else:
			Game.on_full_screen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			$Node2D2/Graphics/FullScreen/AnimationPlayer.play("full_out")
			Game.save_config()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if Game.on_full_screen == false:
			Game.on_full_screen = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			$Node2D2/Graphics/FullScreen/AnimationPlayer.play("selected")
			Game.save_config()
		else:
			Game.on_full_screen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			$Node2D2/Graphics/FullScreen/AnimationPlayer.play("full_out")
			Game.save_config()

func mouse_on_shake():
	if Game.shake_screen == false:
		$Node2D2/Graphics/Shake/AnimationPlayer.play("full_on")
	else:
		$Node2D2/Graphics/Shake/AnimationPlayer.play("selected_out")

func mouse_out_shake():
	if Game.shake_screen == false:
		$Node2D2/Graphics/Shake/AnimationPlayer.play("full_out")
	else:
		$Node2D2/Graphics/Shake/AnimationPlayer.play("selected")

func mouse_selected_shake(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.shake_screen == false:
			Game.shake_screen = true
			$Node2D2/Graphics/Shake/AnimationPlayer.play("selected")
			Game.save_config()
		else:
			Game.shake_screen = false
			$Node2D2/Graphics/Shake/AnimationPlayer.play("full_out")
			Game.save_config()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if Game.shake_screen == false:
			Game.shake_screen = true
			$Node2D2/Graphics/Shake/AnimationPlayer.play("selected")
			Game.save_config()
		else:
			Game.shake_screen = false
			$Node2D2/Graphics/Shake/AnimationPlayer.play("full_out")
			Game.save_config()

func mouse_on_vs():
	if Game.vsync_mode == false:
		$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("full_on")
	else:
		$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("selected_out")

func mouse_out_vs():
	if Game.vsync_mode == false:
		$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("full_out")
	else:
		$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("selected")

func mouse_selected_vs(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.vsync_mode == false:
			Game.vsync_mode = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("selected")
			Game.save_config()
		else:
			Game.vsync_mode = false
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("full_out")
			Game.save_config()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if Game.vsync_mode == false:
			Game.vsync_mode = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("selected")
			Game.save_config()
		else:
			Game.vsync_mode = false
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("full_out")
			Game.save_config()


func setting_status():
	if Game.on_full_screen == true:
		$Node2D2/Graphics/FullScreen/AnimationPlayer.play("selected")
	else:
		$Node2D2/Graphics/FullScreen/AnimationPlayer.play("full_out")
	
	$Node2D2/Graphics/Resolutions.selected = Game.resolution
	
	if Game.shake_screen == true:
		$Node2D2/Graphics/Shake/AnimationPlayer.play("selected")
	else:
		$Node2D2/Graphics/Shake/AnimationPlayer.play("full_out")
	
	if Game.vsync_mode == true:
		$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("selected")
	else:
		$"Node2D2/Graphics/V-Sync/AnimationPlayer".play("full_out")
	

func _on_resolutions_item_selected(index):
	var n: int
	match index:
		0:
			DisplayServer.window_set_size(Vector2i(1280,720))
			n = 0
		1:
			DisplayServer.window_set_size(Vector2i(1600,900))
			n = 1
		2:
			DisplayServer.window_set_size(Vector2i(1920,1080))
			n = 2
	
	Game.resolution = n
	Game.save_config()
