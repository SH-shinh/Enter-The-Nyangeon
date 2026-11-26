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
var _player_focus: Control
var _society_switching := false
# 切社团请求序号：只有最新一次请求能继续改卡片池 / 焦点 / 切换锁（快速连点时「最后点的那张赢」）。
var _society_seq := 0

func _ready():
	SoundManager.cut_finish.connect(bgm_loop_play)
	SoundManager.play_bgm_cut(bgm_first_cut)
	GameEvents.society_card_selected.connect(society_card_filter)
	UIMode.enter_menu()
	GameEvents.player_card_selected.connect(on_level_select)
	GameEvents.level_select_out.connect(out_level_select)
	version.text = Game.version_number
	GameEvents.menu_button.connect(menu_button_press)
	SupportData.reset_game_support()
	ModManager.ensure_unlocked()
	_setup_societies()
	GameEvents.check_data.connect(_sync_societies)
	ExtensionHooks.notify_named("populate_menu_buttons", [menu_button_box])


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
	_player_focus = get_viewport().gui_get_focus_owner()
	on_select_level = true

func out_level_select():
	await get_tree().create_timer(0.1).timeout
	on_select_level = false
	if is_instance_valid(_player_focus) and _player_focus.is_visible_in_tree():
		_player_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if not on_select_anim or not on_select_player or on_select_level or option_menu.on_option:
		return
	var direction := 0
	if event.is_action_pressed("ui_up", true):
		direction = -1
	elif event.is_action_pressed("ui_down", true):
		direction = 1
	if direction == 0:
		return
	# 在 GUI 导航之前消费纵向输入；左右键仍交给角色卡的原生焦点导航。
	get_viewport().set_input_as_handled()
	if event.is_echo() or _society_switching or select_player.is_playing() or menu_anim.is_playing():
		return
	_switch_society(direction)

func _switch_society(direction: int) -> void:
	var cards: Array[Control] = []
	for card in society_card_box.get_children():
		if card is Control and card.visible and not card.is_queued_for_deletion() and card.has_method("on_select_handle"):
			cards.append(card)
	if cards.size() < 2:
		return
	var current := cards.find(society_card_group.back()) if not society_card_group.is_empty() else -1
	var next := 0 if current < 0 else posmod(current + direction, cards.size())
	var target: Control = cards[next]
	SoundManager.play_sfx("ButtonSounds")
	target.on_select_handle()
	var scroll: ScrollContainer = society_card_box.get_parent()
	scroll.ensure_control_visible.call_deferred(target)

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
		i.focus_mode = Control.FOCUS_ALL
	var focusable := _link_menu_button_focus()
	shop_menu.button_open.emit()
	if not focusable.is_empty():
		focusable[0].grab_focus()

func _link_menu_button_focus() -> Array[Control]:
	var buttons: Array[Control] = []
	for child in menu_button_box.get_children():
		if child is not Control or not child.is_visible_in_tree() or child.is_queued_for_deletion():
			continue
		if child.focus_mode == Control.FOCUS_NONE or (child is BaseButton and child.disabled):
			continue
		buttons.append(child)
	for index in buttons.size():
		var button := buttons[index]
		# MOD 可插入或重排入口，不能沿用共用场景中写死的 TestRoom/Option 邻居。
		button.focus_neighbor_top = button.get_path_to(buttons[maxi(index - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(buttons[mini(index + 1, buttons.size() - 1)])
	return buttons

func button_close():
	var buttons: Array = menu_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		i.focus_mode = Control.FOCUS_NONE
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
	# 同一张社团卡重复选中（连点、NewGame 重入）直接忽略：否则 society_card_group 会把它自己
	# out_select_card 掉（on_select 变 false），本次填充循环随即自我取消，卡池被清空。
	if not society_card_group.is_empty() and society_card_group.back() == society_card:
		return
	# 切社团是「最后点的那张赢」：序号在第一个 await 之前领。被覆盖的旧请求在 await 之后
	# 直接返回，不能再碰 _society_switching / 焦点 / 卡片池——player_card_clear_done 是全局信号，
	# 新旧请求会同时被唤醒，旧请求若不退出就会和新请求各填一遍卡，把上一社团的角色混进新卡池。
	_society_seq += 1
	var seq := _society_seq
	_society_switching = true
	society_card_group.push_back(society_card)
	if society_card_group.size() > 1:
		society_card_group[0].out_select_card()
		society_card_group.remove_at(0)
	# 同一个 change_player_card 正在播放时 play() 不会重置播放、method track 不会重放 → 本次请求会
	# 一直等不到 player_card_clear_done（切换锁卡死、卡池不生成）。先 stop 再 play 保证重走 0→0.14s
	# 的清卡 track；只在重播这条动画时 stop，避免打断 select_player / out_player 的滑入滑出。
	if select_player.is_playing() and select_player.current_animation == &"change_player_card":
		select_player.stop()
	select_player.play("change_player_card")
	await player_card_clear_done
	if seq != _society_seq:
		return
	if not on_select_player or not on_select_anim:
		_society_switching = false
		return
	if society_card.has_method("populate_player_cards"):
		await society_card.populate_player_cards(player_card_box)
	if seq != _society_seq:
		return
	_society_switching = false
	if not on_select_player or not on_select_anim:
		change_player_card()
		return
	_link_player_card_focus()
	if not on_select_level and player_card_box.get_child_count() > 0:
		player_card_box.get_child(0).grab_focus()

func _link_player_card_focus() -> void:
	var cards: Array[Control] = []
	for child in player_card_box.get_children():
		if child is Control and not child.is_queued_for_deletion():
			cards.append(child)
	for index in cards.size():
		var card := cards[index]
		# 动画不断改变卡片宽度；固定左右目标，避免几何导航误入卡内分支按钮。
		var left := cards[maxi(index - 1, 0)]
		var right := cards[mini(index + 1, cards.size() - 1)]
		card.focus_neighbor_left = card.get_path_to(left)
		card.focus_neighbor_right = card.get_path_to(right)
		var branch: Control = card.get("branch_button")
		if is_instance_valid(branch):
			branch.focus_neighbor_left = branch.get_path_to(left)
			branch.focus_neighbor_right = branch.get_path_to(right)

func change_player_card():
	for child in player_card_box.get_children():
		# 立即摘出树再排队释放：queue_free 要到帧末才真正移除，留着会让同帧填入的新角色卡
		# 排在待释放旧卡之后，首卡 / 焦点 / 布局都按旧顺序算。
		player_card_box.remove_child(child)
		child.queue_free()
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
