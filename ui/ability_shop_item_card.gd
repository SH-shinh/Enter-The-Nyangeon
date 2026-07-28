extends PanelContainer

@export var equip_card: Equip
@export var is_test: bool = false

@onready var texture_rect = $Node2D/ColorRect2/TextureRect
@onready var label = $Node2D/ColorRect2/Label
@onready var cost = $Node2D/upgrade/Node2D/ColorRect/Label
@onready var smoke = preload("res://scenes/bullet/spread_smoke.tscn")
@onready var marker_2d = $Marker2D
@onready var text_follow = $Node2D2
@onready var equip_text = $Node2D2/PanelContainer/Label
@onready var upgrade = $Node2D/upgrade
@onready var color_rect = $Node2D/ColorRect2

@onready var equip_t = $Node2D3/PanelContainer/VBoxContainer/Label
@onready var equip_t_2 = $Node2D3/PanelContainer/VBoxContainer/Label2

@onready var equip_text_p = $Node2D/EquipTextP
@onready var node_2d_3 = $Node2D3


var t_num: int = 0
var icon_num: int = 0
var coin_cost:int = 0

var player: Node

var cost_mult: float = 1.5

var on_text_follow: bool = false

var rare_color: Array[Color] =[ Color(0.779, 0.795, 0.81), Color(0.464, 0.673, 0.832), Color(0.884, 0.764, 0.435), Color(0.985, 0.643, 0.909) ]

var on_touch: bool = false

func _ready():
	upgrade.mouse_entered.connect(mouse_in)
	upgrade.mouse_exited.connect(mouse_out)
	equip_text_p.mouse_entered.connect(text_show)
	equip_text_p.mouse_exited.connect(text_hide)
	upgrade.gui_input.connect(mouse_selected)
	equip_text_p.gui_input.connect(mouse_selected)
	GameEvents.get_player.connect(get_player)
	GameEvents.player_card_touch.connect(touch_out)
	texture_rect.texture = equip_card.icon[icon_num]
	cost_count()
	item_text_get()
	item_text_count()

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	reset_data()

func reset_data():
	t_num = 0
	icon_num = 0
	coin_cost = 0
	cost_count()
	item_text_get()
	item_text_count()
	texture_rect.texture = equip_card.icon[icon_num]
	label.text = "T" + str(t_num)
	upgrade.mouse_filter = 0

func _process(delta):
	if on_text_follow == true:
		if on_touch == false:
			text_follow.global_position = get_global_mouse_position()
			node_2d_3.global_position = get_global_mouse_position()
		else:
			text_follow.global_position = self.global_position
			node_2d_3.global_position = self.global_position
			text_follow.position = Vector2(0, 0)
			node_2d_3.position = Vector2(0, -20)

func text_show():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D/upgrade/AnimationPlayer.play("mouse_in")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")
	if t_num > 0:
		on_text_follow = true
		node_2d_3.visible = true

func text_hide():
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")
	if t_num > 0:
		on_text_follow = false
		node_2d_3.visible = false

func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D/upgrade/AnimationPlayer.play("mouse_in")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")
	on_text_follow = true
	text_follow.visible = true

func mouse_out():
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")
	on_text_follow = false
	text_follow.visible = false

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_touch == true:
		on_touch = false
		$Node2D/upgrade/AnimationPlayer.play("mouse_out")
		$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")
		on_text_follow = false
		node_2d_3.visible = false
		text_follow.visible = false

func mouse_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			$Node2D/upgrade/AnimationPlayer.play("mouse_in")
			$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")
			on_text_follow = true
			if t_num > 0:
				node_2d_3.visible = true
			text_follow.visible = true
			
		else:
			
			if t_num >= 20:
				$Node2D/upgrade/AnimationPlayer.play("coin_lack")
				return
			
			if player.stats.usable_coin < coin_cost:
				$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			else:
				SoundManager.play_sfx("ButtonSounds")
				GameEvents.emit_player_coins_cost(coin_cost)
				item_upgrade()
				add_ability()
	
	if event.is_action_pressed("shoot"):
		
		if t_num >= 20:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return
		
		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			add_ability()

func cost_count():
	if is_test == false:
		coin_cost = round(float(pow(cost_mult,1)) + float(pow(cost_mult,1.5)) * float(pow(cost_mult,1.5)))
		cost.text = str(coin_cost)
	else:
		coin_cost = 0
		cost.text = "FREE"

func item_text_get():
	var text_1: String = ""
	var text_2: String = ""
	
	if t_num <= 6:
		color_rect.color = rare_color[0]
	elif t_num <= 12 and t_num > 6:
		color_rect.color = rare_color[1]
	elif t_num <= 18 and t_num > 12:
		color_rect.color = rare_color[2]
	else:
		color_rect.color = rare_color[3]
	
	if t_num < 20:
		if !equip_card.value_1.is_empty():
			if equip_card.value_1[t_num + 1] > 0:
				equip_text.text = "+" + str( equip_card.value_1[t_num + 1] ) + tr(equip_card.value_1_name)
			else:
				equip_text.text = "-" + str( equip_card.value_1[t_num + 1] ) + tr(equip_card.value_1_name)
			text_1 = equip_text.text + "  "
		if !equip_card.value_2.is_empty():
			if equip_card.value_2[t_num + 1] > 0:
				if equip_card.value_2[t_num + 1] < 1:
					equip_text.text = text_1 + "+" + str( equip_card.value_2[t_num + 1] * 100 ) + "%" + tr(equip_card.value_2_name)
				else:
					if equip_card.value_2_name == "player_critical":
						equip_text.text = text_1 + "+" + str( equip_card.value_2[t_num + 1] ) + "%" + tr(equip_card.value_2_name)
					else:
						equip_text.text = text_1 + "+" + str( equip_card.value_2[t_num + 1] ) + tr(equip_card.value_2_name)
			elif equip_card.value_2[t_num + 1] < 0:
				equip_text.text = text_1 + str( equip_card.value_2[t_num + 1] * 100 ) + "%" + tr(equip_card.value_2_name)
			text_2 = equip_text.text + "  "
		if !equip_card.value_3.is_empty():
			if equip_card.value_3[t_num + 1] > 0:
				if equip_card.value_3[t_num + 1] < 1:
					if equip_card.value_3_name == "player_damage_taken":
						equip_text.text = text_2 + "-" + str( equip_card.value_3[t_num + 1] * 100 ) + "%" + tr(equip_card.value_3_name)
					elif equip_card.value_3_name == "player_reload_speed":
						equip_text.text = text_2 + "+" + str(  (1 - equip_card.value_3[t_num + 1]) * 100 ) + "%" + tr(equip_card.value_3_name)
					elif equip_card.value_3_name == "player_coin_refund":
						equip_text.text = text_2 + "+" + str( equip_card.value_3[t_num + 1] * 100 ) + "%" + tr(equip_card.value_3_name)
				else:
					if equip_card.value_3_name == "player_damage_taken":
						equip_text.text = text_2 + "-" + str( equip_card.value_3[t_num + 1] ) + "%" + tr(equip_card.value_3_name)
					else:
						equip_text.text = text_2 + "+" + str( equip_card.value_3[t_num + 1] ) + tr(equip_card.value_3_name)
			elif equip_card.value_3[t_num + 1] < 0:
				equip_text.text = text_2 + str( equip_card.value_3[t_num + 1] * 100 ) + "%" + tr(equip_card.value_3_name)
		
	else:
		equip_text.text = "已到达升级上限"

func item_text_count():
	
	equip_t.text = label.text
	
	var text_1_c: String = ""
	var text_2_c: String = ""
	
	var value_1 = 0
	var value_2 = 0
	var value_3 = 0
	
	if !equip_card.value_1.is_empty():
		for i in (t_num + 1):
			value_1 += equip_card.value_1[i]
	
	if !equip_card.value_2.is_empty():
		for i in (t_num + 1):
			value_2 += equip_card.value_2[i]
	
	if !equip_card.value_3.is_empty():
		if equip_card.value_3_name == "player_reload_speed":
			for i in (t_num + 1):
				value_3 += (1 - equip_card.value_3[i])
		else:
			for i in (t_num + 1):
				value_3 += equip_card.value_3[i]
	
	if !equip_card.value_1.is_empty():
		if value_1 >= 0:
			equip_t_2.text = "+" + str( value_1 ) + tr(equip_card.value_1_name)
		else:
			equip_t_2.text = "-" + str( value_1 ) + tr(equip_card.value_1_name)
		text_1_c = equip_t_2.text + "  "
	if !equip_card.value_2.is_empty():
		if value_2 >= 0:
			if value_2 < 1 or equip_card.value_2_name == "player_pickup_range":
				if equip_card.value_2_name != "player_armor":
					equip_t_2.text = text_1_c + "+" + str( value_2 * 100 ) + "%" + tr(equip_card.value_2_name)
			else:
				if equip_card.value_2_name == "player_critical":
					equip_t_2.text = text_1_c + "+" + str( value_2 ) + "%" + tr(equip_card.value_2_name)
				else:
					equip_t_2.text = text_1_c + "+" + str( value_2 ) + tr(equip_card.value_2_name)
		elif value_2 < 0:
			equip_t_2.text = text_1_c + str( value_2 * 100 ) + "%" + tr(equip_card.value_2_name)
		text_2_c = equip_t_2.text + "  "
	if !equip_card.value_3.is_empty():
		if value_3 >= 0:
			if value_3 < 1 or equip_card.value_3_name == "player_pickup_range":
				if equip_card.value_3_name == "player_damage_daken":
					equip_t_2.text = text_2_c + "-" + str( value_3 * 100 ) + "%" + tr(equip_card.value_3_name)
				elif equip_card.value_3_name == "player_reload_speed":
					equip_t_2.text = text_2_c + "+" + str( round(value_3 * 100) ) + "%" + tr(equip_card.value_3_name)
				elif equip_card.value_3_name == "player_coin_refund":
					equip_t_2.text = text_2_c + "+" + str( round(value_3 * 100) ) + "%" + tr(equip_card.value_3_name)
			elif equip_card.value_3_name == "player_reload_speed":
					equip_t_2.text = text_2_c + "+" + str( round(value_3 * 100) ) + "%" + tr(equip_card.value_3_name)
			else:
				if equip_card.value_3_name == "player_critical":
					equip_t_2.text = text_2_c + "+" + str( value_3 ) + "%" + tr(equip_card.value_3_name)
				else:
					equip_t_2.text = text_2_c + "+" + str( value_3 ) + tr(equip_card.value_3_name)
		elif value_3 < 0:
			equip_t_2.text = text_2_c + str( value_3 * 100 ) + "%" + tr(equip_card.value_3_name)

func smoke_anim():
	var ins = smoke.instantiate()
	ins.position = marker_2d.position
	add_child(ins)

func item_upgrade():
	if t_num >= 20:
		return
	
	t_num += 1
	cost_mult += 0.3
	cost_count()
	item_text_get()
	var v = round((t_num + 1) / 2)
	if icon_num != v:
		icon_num = v
		smoke_anim()
		texture_rect.texture = equip_card.icon[icon_num]
		label.text = "T" + str(v)
	item_text_count()
	if t_num >= 20:
		upgrade.mouse_filter = 2
		cost.text = "MAX"


func add_ability():
	
	if !equip_card.value_1.is_empty():
		var first = PlayerData.get( equip_card.value_1_id )
		PlayerData.set( equip_card.value_1_id , first + equip_card.value_1[t_num] )
	if !equip_card.value_2.is_empty():
		var first = PlayerData.get( equip_card.value_2_id )
		PlayerData.set( equip_card.value_2_id , first + equip_card.value_2[t_num] )
	if !equip_card.value_3.is_empty():
		if equip_card.value_3_name == "player_reload_speed":
			var first = PlayerData.get( equip_card.value_3_id )
			PlayerData.set( equip_card.value_3_id , first * equip_card.value_3[t_num] )
		else:
			var first = PlayerData.get( equip_card.value_3_id )
			PlayerData.set( equip_card.value_3_id , first + equip_card.value_3[t_num] )
	
	PlayerData.update_player_ability()
