extends CanvasLayer

signal player_card_clear_done

@export var bgm_first_cut: AudioStream
@export var bgm_loop: AudioStream

@onready var menu_anim = $AnimationPlayer
@onready var select_player = $SelectPlayer/AnimationPlayer
@onready var player_card_box = $SelectPlayer/Node2D2/MarginContainer/PlayerCardBox
@onready var society_card_box = $SelectPlayer/Node2D/SocietyCardBox/ScrollContainer/VBoxContainer
@onready var option_menu = $OptionMenu
@onready var shop_menu: Node2D = $Node2D6/ShopMenu
@onready var version: Label = %version
@onready var scoreboard: Control = $scoreboard
@onready var score_button = $Node2D6/TextureRect2/score_button
@onready var credits: Control = $Credits
@onready var credits_button: Button = $Node2D5/credits_button

const MOD_SOCIETY_SCENE := preload("res://ui/mod_society_card.tscn")
const MOD_PAGE_SIZE := 4
@onready var menu_button_box = $Node2D5/menu_button_box

var on_select_anim: bool = false
var on_select_player: bool = false
var on_select_level: bool = false

var test_room_on_touch: bool = false
var new_game_on_touch: bool = false
var option_on_touch: bool = false
var quit_on_touch: bool = false

var society_card_group: Array[Node] = []
var _default_society: Node = null
var _society_gids: Array = []

func _ready():
	SoundManager.cut_finish.connect(bgm_loop_play)
	SoundManager.play_bgm_cut(bgm_first_cut)
	GameEvents.society_card_selected.connect(society_card_filter)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameEvents.player_card_selected.connect(on_level_select)
	GameEvents.level_select_out.connect(out_level_select)
	version.text = Game.version_number
	GameEvents.menu_button.connect(menu_button_press)
	SupportData.reset_game_support()
	ModManager.ensure_unlocked()
	_setup_societies()
	GameEvents.check_data.connect(_sync_societies)
	if ExtensionHooks.populate_menu_buttons.is_valid():
		ExtensionHooks.populate_menu_buttons.call(menu_button_box)


# 只实例化「已解锁」的社团（本体注册表 + mod 社团 + MOD 通用卡）。
func _setup_societies() -> void:
	for child in society_card_box.get_children():
		society_card_box.remove_child(child)
		child.queue_free()
	society_card_group.clear()
	_default_society = null
	for s in ModManager.get_base_societies():
		if not PlayerData.group.has(str(s.get("group_id", ""))):
			continue
		var base_scene = s.get("scene")
		if base_scene != null:
			society_card_box.add_child(base_scene.instantiate())
	for s in ModManager.get_mod_societies():
		if not PlayerData.group.has(str(s.get("group_id", ""))):
			continue
		var scene = s.get("scene")
		if scene != null:
			society_card_box.add_child(scene.instantiate())
	# 通用「MOD」社团卡：每 MOD_PAGE_SIZE 个未认领角色一张，>4 时自动续卡（MOD / MOD 2 / …）。
	var mod_ids := _mod_generic_ids()
	var mod_pages := int(ceil(float(mod_ids.size()) / MOD_PAGE_SIZE))
	for p in mod_pages:
		var card := MOD_SOCIETY_SCENE.instantiate()
		var slice: Array[String] = []
		for i in range(MOD_PAGE_SIZE):
			var idx := p * MOD_PAGE_SIZE + i
			if idx < mod_ids.size():
				slice.append(mod_ids[idx])
		card.set("members", slice)
		if card.has_method("set_page"):
			card.call("set_page", p, mod_pages)
		society_card_box.add_child(card)
	_society_gids = _current_unlocked_gids()
	_default_society = _first_society()


func _current_unlocked_gids() -> Array:
	var out: Array = []
	for s in ModManager.get_base_societies():
		var gid = str(s.get("group_id", ""))
		if PlayerData.group.has(gid):
			out.append(gid)
	for s in ModManager.get_mod_societies():
		var gid = str(s.get("group_id", ""))
		if PlayerData.group.has(gid):
			out.append(gid)
	if not ModManager.get_unclaimed_unlocked_characters().is_empty():
		out.append("__mod_generic__:%d" % _mod_generic_ids().size())
	return out


# 未认领且已解锁的 mod 角色 id（通用「MOD」社团卡分组用）。
func _mod_generic_ids() -> Array[String]:
	var out: Array[String] = []
	for card in ModManager.get_unclaimed_unlocked_characters():
		if card != null:
			out.append(str(card.id))
	return out


func _first_society() -> Node:
	for c in society_card_box.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			return c
	return null


# 解锁集合变化时才重建社团列（check_data 在菜单交互时也会发，用差异判断挡掉）。
func _sync_societies() -> void:
	if _current_unlocked_gids() == _society_gids:
		return
	_setup_societies()


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
	var buttons: Array = menu_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_menu.button_open.emit()

func button_close():
	var buttons: Array = menu_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_menu.button_close.emit()

func bgm_loop_play():
	SoundManager.play_bgm(bgm_loop)

func menu_button_press(button_id: String):
	
	match button_id:
		
		"new_game":
			menu_anim.play("select_anim")
			select_player.play("select_player")
			await select_player.animation_finished
			if _default_society != null and is_instance_valid(_default_society):
				_default_society.on_select_handle()
		
		"test_room":
			SoundManager.bgm_fade_out()
			Transition.play_left_start()
			await Transition.left_end_start
			GameEvents.change_scene("res://scenes/main/test_room.tscn","res://scenes/player/momoi/momoi.tscn")
		
		"option_menu":
			button_close()
			menu_anim.play("select_anim")
			option_menu.on_option_selected()
		
		"game_quit":
			button_close()
			get_tree().quit()
		
		_:
			return
	
	button_close()

func society_card_filter(society_card: Node):
	society_card_group.push_back(society_card)
	if society_card_group.size() > 1:
		society_card_group[0].out_select_card()
		society_card_group.remove_at(0)
	select_player.play("change_player_card")
	await player_card_clear_done
	if society_card.has_method("populate_player_cards"):
		await society_card.populate_player_cards(player_card_box)

func change_player_card():
	var cards = player_card_box.get_children()
	for i in cards.size():
		cards[i].queue_free()
	player_card_clear_done.emit()

func _on_score_button_pressed() -> void:
	SoundManager.play_sfx("UISounds2")
	scoreboard.show_scoreboard()

func _is_button_press(event: InputEvent) -> bool:
	if event as InputEventScreenTouch and event.pressed:
		return true
	if event as InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	return false

func _on_score_button_gui_input(event: InputEvent) -> void:
	if _is_button_press(event):
		score_button.accept_event()
		_on_score_button_pressed()

func _on_credits_button_pressed() -> void:
	SoundManager.play_sfx("UISounds2")
	GameEvents.emit_player_card_touch()
	credits.show_credits()

func _on_credits_button_gui_input(event: InputEvent) -> void:
	if _is_button_press(event):
		credits_button.accept_event()
		_on_credits_button_pressed()
