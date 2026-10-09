extends CanvasLayer

signal upgrade_selected(upgrade:AbilityUpgrade)
signal upgrade_reselect

var coin_cost: int = 0
var player: Node

var joy_box: Array[Node]
var joy_index: int = -1
var can_joy: bool = true

var is_next: bool = false
var is_refresh: bool = false
var _closed: bool = false

var on_menu: bool = true
var menu_index: int = 0

@export var upgrade_card_scene: PackedScene

@onready var card_container: HBoxContainer = $%CardContainer
@onready var next = %Next
@onready var refresh = %Refresh

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	if player != null:
		player.gun.is_shoot = false
	GameEvents.refresh_cost_count.connect(get_refresh_cost)
	refresh.mouse_entered.connect(refresh_on_selected)
	refresh.mouse_exited.connect(refresh_exit_selected)
	refresh.gui_input.connect(on_refresh)
	next.mouse_entered.connect(next_on_selected)
	next.mouse_exited.connect(next_exit_selected)
	next.gui_input.connect(on_next_round)
	GameEvents.emit_on_refresh()
	GameEvents.menu_changed.connect(get_menu_changed)
	_build_ready_indicators()
	GameEvents.upgrade_ready_changed.connect(_on_upgrade_ready_changed)

# 联机：队友就绪指示（代码构建，最多 3 个槽位，对应除自己外的玩家）
var _ready_labels: Array[Label] = []

func _build_ready_indicators() -> void:
	for i in 3:
		var l := Label.new()
		l.text = "P%d READY" % (i + 2)
		l.visible = false
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", 4)
		l.position = Vector2(16, 16 + i * 22)
		l.modulate.a = 0.28
		add_child(l)
		_ready_labels.append(l)

func _on_upgrade_ready_changed(slot: int, is_ready: bool) -> void:
	if slot <= 0:
		for l in _ready_labels:
			l.visible = true
			l.modulate.a = 0.28
		return
	var idx: int = slot - 1
	if idx < 0 or idx >= _ready_labels.size():
		return
	_ready_labels[idx].visible = true
	_ready_labels[idx].modulate.a = 1.0 if is_ready else 0.28

func _unhandled_input(event):
	if on_menu:
		joy_select(event)

func get_menu_changed(changed_index):
	if changed_index == menu_index:
		await get_tree().process_frame
		on_menu = true

func joy_select(event: InputEvent):
	if event.is_action_pressed("ui_down"):
		SoundManager.play_sfx("ButtonSounds2")
		on_menu = false
		var now_menu_index = wrapi(menu_index + 1, 0, 2)
		GameEvents.emit_menu_changed(now_menu_index)
	elif event.is_action_pressed("ui_up"):
		SoundManager.play_sfx("ButtonSounds2")
		on_menu = false
		var now_menu_index = wrapi(menu_index - 1, 0, 2)
		GameEvents.emit_menu_changed(now_menu_index)
	
	if can_joy:
		can_joy = false
		if !card_container.get_children().is_empty():
			joy_box.clear()
			joy_box = card_container.get_children()
			joy_box.append(refresh)
			joy_box.append(next)
		
		if !joy_box.is_empty():
			if joy_box[0] == null:
				joy_box.clear()
				joy_box.append(refresh)
				joy_box.append(next)
				joy_index = 0
		
		if event.is_action_pressed("ui_left"):
			joy_index = wrapi(joy_index - 1, 0, joy_box.size())
			if is_next:
				next_exit_selected()
			if is_refresh:
				refresh_exit_selected()
			joy_button()
		
		elif event.is_action_pressed("ui_right"):
			joy_index = wrapi(joy_index + 1, 0, joy_box.size())
			if is_next:
				next_exit_selected()
			if is_refresh:
				refresh_exit_selected()
			joy_button()
		
		elif event.is_action_pressed("ui_accept"):
			joy_button()
		await get_tree().process_frame
		can_joy = true

func joy_button():
	
	if joy_box[joy_index] == next:
		GameEvents.emit_player_card_touch()
		if !is_next:
			next_on_selected()
		else:
			next_round_button()
	elif joy_box[joy_index] == refresh:
		GameEvents.emit_player_card_touch()
		if !is_refresh:
			refresh_on_selected()
		else:
			refresh_button()
	else:
		joy_box[joy_index].button_pressed()

func close_mouse():
	$%Refresh.mouse_filter = 2
	$%Next.mouse_filter = 2

func set_ability_upgrades(upgrades: Array[AbilityUpgrade]):
	var delay: float = 0
	for upgrade in upgrades:
		var card_instance = upgrade_card_scene.instantiate()
		card_container.add_child(card_instance)
		card_instance.set_ability_upgrade(upgrade)
		card_instance.play_card_in(delay)
		card_instance.selected.connect(on_upgrade_selected.bind(upgrade))
		delay += 0.1

func on_upgrade_selected(upgrade:AbilityUpgrade):
	for i in card_container.get_children():
		i.can_select = false
		i.card_dis()
	upgrade_selected.emit(upgrade)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func next_on_selected():
	SoundManager.play_sfx("ButtonSounds2")
	$%Next/AnimationPlayer.play("selected")
	is_next = true

func next_exit_selected():
	if !$%Next/AnimationPlayer :
		return
	$%Next/AnimationPlayer.play("exit_selected")
	is_next = false

func refresh_on_selected():
	SoundManager.play_sfx("ButtonSounds2")
	$%Refresh/AnimationPlayer.play("select")
	is_refresh = true

func refresh_exit_selected():
	if !$%Refresh/AnimationPlayer :
		return
	$%Refresh/AnimationPlayer.play("exit_selected")
	is_refresh = false

func get_refresh_cost(refresh_cost: int):
	$Node2D3/Refresh/Node2D2/Label.text = str("-",refresh_cost)
	coin_cost = refresh_cost

func on_refresh(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		refresh_button()
	
	if event.is_action_pressed("shoot"):
		refresh_button()

func refresh_button():
	if _closed:
		return
	if player != null and player.stats.usable_coin < coin_cost:
		$Node2D3/Refresh/AnimationPlayer.play("coin_lack")
		SoundManager.play_sfx("ButtonSounds2")
		return
	_closed = true
	SoundManager.play_sfx("ButtonSounds")
	GameEvents.emit_refresh_coin_cost(coin_cost)
	upgrade_reselect.emit()
	close_mouse()
	queue_free()

func on_next_round(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		next_round_button()
	
	if event.is_action_pressed("shoot"):
		next_round_button()

func next_round_button():
	if _closed:
		return
	_closed = true
	SoundManager.play_sfx("ButtonSounds")
	GameEvents.emit_round_upgrade_closing()
	GameEvents.emit_round_upgrade_end()
	close_mouse()
	await Transition.left_end_start
	queue_free()
