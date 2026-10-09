extends CanvasLayer

@export var player: Node
@export var stats: Stats

@onready var hp_bar = $%HP_BAR
@onready var hp_bar_3 = $%HP_BAR_3
@onready var hp_val = $%HP_VAL
@onready var temporary_hp_bar = %Temporary_HP_BAR
@onready var temporary_hp_bar_2 = %Temporary_HP_BAR2
@onready var t_hp_val = %T_HP_VAL
@onready var coin = $%Coin
@onready var ammo = $%Ammo
@onready var buff_box = $%HBoxContainer
@onready var player_icon = %PlayerIcon
@onready var player_name = %PlayerName
@onready var weapon_name = %WeaponName
@onready var virtual_joypad = $VirtualJoypad
@onready var support_box: VBoxContainer = %support_box
@onready var life_value: Label = %Life_value

signal is_hurt()

func _ready():
	stats.hp_changed.connect(update_hp )
	stats.coin_changed.connect(update_coin )
	stats.is_hurt.connect(hurt_anim)
	stats.ammo_changed.connect(update_ammo)
	stats.max_ammo_changed.connect(update_ammo)
	GameEvents.game_over.connect(game_over_hide)
	GameEvents.ui_visible.connect(game_ui_visible)
	Game.game_mode_changed.connect(check_game_mode)
	GameEvents.round_start.connect(check_game_mode)
	update_hp()
	update_coin()
	update_ammo()
	get_player_card()
	check_game_mode()

func check_game_mode():
	if Game.control_mode != 1:
		virtual_joypad.visible = false
	else:
		virtual_joypad.visible = true
		var has_support: bool = SupportData.game_support != null and SupportData.game_support.support_id != "null"
		$VirtualJoypad/Actions/TouchScreenButton4.visible = has_support

func get_player_card():
	player_icon.texture = LazyTexture.load_uncached(player.player_card.sprite_path)
	player_name.text = player.player_card.name
	weapon_name.text = player.player_card.weapon
	weapon_name.set("theme_override_colors/font_color", player.player_card.color)

func game_ui_visible(now_visible: bool):
	visible = now_visible

func game_over_hide(player_dead: bool):
	visible = false

func update_ammo():
	if stats.bullet_cost > 0:
		ammo.text = str( str(stats.ammo) + "/" + str(stats.max_ammo) )
	else:
		ammo.text = "∞"

func update_hp():
	var percentage := stats.hp / float( stats.max_hp )
	hp_val.text = str( str(stats.hp),"/",str(stats.max_hp) )
	if stats.life_num > 0:
		life_value.visible = true
		if stats.life_num < 100:
			life_value.text = "x" + str(stats.life_num + 1)
		else:
			life_value.text = "x∞"
	else:
		life_value.visible = false
	
	if stats.t_hp > 0:
		var percentage_2 := stats.t_hp / float( stats.max_hp )
		var t_v := percentage_2 + percentage
		
		t_hp_val.visible = true
		t_hp_val.text = str("+",str(stats.t_hp))
		
		if t_v > 1:
			var t_v_2 = t_v - 1
			
			if t_v_2 > 1:
				t_v_2 = 1
			
			create_tween().tween_property(temporary_hp_bar_2, "value", 1, 0.05 )
			create_tween().tween_property(temporary_hp_bar, "value", t_v_2, 0.05 )
		else:
			create_tween().tween_property(temporary_hp_bar_2, "value", t_v, 0.05 )
			create_tween().tween_property(temporary_hp_bar, "value", 0, 0.05 )
		
	else:
		t_hp_val.visible = false
		t_hp_val.text = str("+",str(0))
		create_tween().tween_property(temporary_hp_bar_2, "value", 0, 0.05 )
		create_tween().tween_property(temporary_hp_bar, "value", 0, 0.05 )
	
	create_tween().tween_property(hp_bar, "value", percentage, 0.05 )
	create_tween().tween_property(hp_bar_3, "value", percentage, 0.3 )
	create_tween().tween_property(hp_bar_3, "tint_progress",Color(0.884, 0, 0.603) , 0.15 ).from(Color(1, 1, 1))

func update_coin():
	coin.text = str( stats.coin )
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(coin, "position", Vector2(11, 3), 0.1).from(Vector2(11, -8))

func hurt_anim():
	var v = randi_range(0,1)
	$Timer.start()
	if v == 0:
		player_icon.frame = 3
	else:
		player_icon.frame = 1
	
	
	
	var tween = get_tree().create_tween().set_parallel(true)
	hp_bar.material.set_shader_parameter("flash_opacity", 1)
	tween.tween_property($MarginContainer/HpValue, "position", Vector2(0,0), 0.025).from(Vector2(randf_range(-10,10), randf_range(-12,12)))
	tween.tween_property($TextureRect, "position", Vector2(0,-5), 0.025).from(Vector2(randf_range(-10,10), randf_range(-17,7)))
	tween.chain()
	tween.tween_property($MarginContainer/HpValue, "position", Vector2(0,0), 0.025).from(Vector2(randf_range(-10,10), randf_range(-12,12)))
	tween.tween_property($TextureRect, "position", Vector2(0,-5), 0.025).from(Vector2(randf_range(-10,10), randf_range(-17,7)))
	tween.chain()
	tween.tween_property($MarginContainer/HpValue, "position", Vector2(0,0), 0.025).from(Vector2(randf_range(-10,10), randf_range(-12,12)))
	tween.tween_property($TextureRect, "position", Vector2(0,-5), 0.025).from(Vector2(randf_range(-10,10), randf_range(-17,7)))
	tween.chain()
	tween.tween_property($MarginContainer/HpValue, "position", Vector2(0,0), 0.025).from(Vector2(randf_range(-10,10), randf_range(-12,12)))
	tween.tween_property($TextureRect, "position", Vector2(0,-5), 0.025).from(Vector2(randf_range(-10,10), randf_range(-17,7)))
	await tween.finished
	hp_bar.material.set_shader_parameter("flash_opacity", 0)
	$Timer.start()

func _on_timer_timeout():
	player_icon.frame = 0
	
