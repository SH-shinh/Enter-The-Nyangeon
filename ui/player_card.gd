extends PanelContainer

const BRANCH_BUTTON: PackedScene = preload("res://ui/branch_button.tscn")

@export_file("*.tscn") var path: String
@export_file("*.tscn") var player: String
@export var player_card: PlayerCard

@onready var card_anim = $AnimationPlayer
@onready var player_p = $%PlayerP
@onready var player_pbg = $ColorRect/Node2D/PlayerPBG
@onready var name_label: Label = $ColorRect/Node2D/Node2D/ColorRect/Label
@onready var weapon_label: Label = $ColorRect/Node2D/Node2D/ColorRect/Label2
@onready var ps_label: Label = $ColorRect/Node2D/Node2D/Node2D/Label
@onready var color_rect = $ColorRect/Node2D/Node2D/ColorRect

var on_select: bool = false
var on_touch: bool = false

var branch_list: Array[PlayerCard] = []
var branch_index: int = 0
var cur: PlayerCard
var _revealed_path: String = ""

var branch_button: Control = null
var _hovered: bool = false
var _switching: bool = false
var _touch_mode: bool = false

func _ready():
	card_anim.play("add_card")
	card_anim.animation_finished.connect(_on_card_anim_finished)
	gui_input.connect(add_player)
	GameEvents.player_card_selected.connect(mouse_close)
	GameEvents.level_select_out.connect(mouse_open)
	GameEvents.player_card_touch.connect(touch_out_player_card)
	ps_label.text = _ps_text(player_card, 0)
	_build_branch_list()
	_setup_branch_button()
	reveal()

func _build_branch_list():
	branch_list = [player_card]
	for b in player_card.branches:
		if PlayerData.character.has(b.id):
			branch_list.append(b)
	if player_card.scene_path != "":
		player = player_card.scene_path

func _setup_branch_button():
	if branch_list.size() <= 1:
		return
	branch_button = BRANCH_BUTTON.instantiate()
	color_rect.add_child(branch_button)
	branch_button.position = Vector2(15, -55)
	branch_button.pressed.connect(switch_branch)


func _input(event: InputEvent):
	if event is InputEventScreenTouch:
		_touch_mode = true
	elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_touch_mode = false


func _process(_delta):
	if _touch_mode:
		return
	if _switching:
		return
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	_apply_hover()


# 逐帧轮询悬停：鼠标在卡片矩形内、或在分支按钮矩形内（含按钮尚未显示时）都算悬停。
# 轮询避免事件式的 1 帧延迟与快移漏判；按钮区域也算热区，移过去即可触发并显示按钮。
func _apply_hover():
	var m := get_global_mouse_position()
	var over := get_global_rect().has_point(m)
	if not over and branch_button != null and is_instance_valid(branch_button):
		over = branch_button.get_global_rect().has_point(m)
	if over == _hovered:
		return
	_hovered = over
	if over:
		select_player_card()
	else:
		select_out_player_card()


func _on_card_anim_finished(anim_name: StringName):
	if anim_name == "branch_anim":
		_switching = false
		# RESET 会把 mouse_filter 设成 IGNORE，这里恢复可交互
		mouse_filter = Control.MOUSE_FILTER_STOP
		var m := get_global_mouse_position()
		var over := get_global_rect().has_point(m)
		if not over and branch_button != null and is_instance_valid(branch_button):
			over = branch_button.get_global_rect().has_point(m)
		_hovered = over
		if over:
			# 瞬间套用 select_card 末帧（尺寸/位置/显示带），不播放过程、无音效
			card_anim.play("select_card")
			card_anim.seek(card_anim.get_animation("select_card").length, true)


func switch_branch():
	if branch_list.size() <= 1:
		return
	branch_index = (branch_index + 1) % branch_list.size()
	cur = branch_list[branch_index]
	player_card = cur
	player = cur.scene_path
	_switching = true
	card_anim.play("RESET")
	card_anim.play("branch_anim")

func _update_visual():
	_apply_sprite(cur.sprite_path)
	name_label.text = cur.name
	weapon_label.text = cur.weapon
	ps_label.text = _ps_text(cur, 0)


# 本地化缺失时回退到角色描述，避免显示原始键（如 xxx_ps_0）
func _ps_text(card: PlayerCard, idx: int) -> String:
	if card == null:
		return ""
	var key := card.id + "_ps_" + str(idx)
	var t := tr(key)
	return t if t != key else str(card.description)


# 立绘大图按需加载/释放（不缓存）。列表滚动可见性由外部调用 reveal/conceal。
func reveal() -> void:
	var card: PlayerCard = cur if cur != null else player_card
	if card == null:
		return
	_apply_sprite(card.sprite_path)


func conceal() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""
	player_p.texture = null
	player_pbg.texture = null


func _apply_sprite(path: String) -> void:
	if _revealed_path == path and player_p.texture != null:
		return
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""
	var tex := LazyTexture.acquire(path)
	player_p.texture = tex
	player_pbg.texture = tex
	_revealed_path = path


func _exit_tree() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""

func mouse_open():
	mouse_filter = 0
	if on_select == true:
		card_anim.play("select_out")
		on_select = false
		on_touch = false

func mouse_close():
	mouse_filter = 2

func select_player_card():
	SoundManager.play_sfx("ButtonSounds2")
	card_anim.play("select_card")

func select_out_player_card():
	if on_select == false:
		card_anim.play("select_out")

func touch_out_player_card():
	
	await get_tree().create_timer(0.05).timeout
	
	if on_select == false and on_touch == true:
		on_touch = false
		card_anim.play("select_out")

func play_voice():
	var n = randi_range(0,1)
	if n == 0:
		SoundManager.play_voice(player_card.voice_name, "SelectVoice1")
	else:
		SoundManager.play_voice(player_card.voice_name, "SelectVoice2")

func add_player(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			card_anim.play("select_card")
			
		else:
			SoundManager.play_sfx("ButtonSounds")
			if player != "":
				play_voice()
				on_select = true
				GameEvents.emit_player_card_selected()
				GameEvents.emit_player_card_id(player)
				card_anim.play("select_anim")
				SupportData.reset_game_support()
				await card_anim.animation_finished
				GameEvents.emit_level_select_in()
	
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if player != "":
			play_voice()
			on_select = true
			GameEvents.emit_player_card_selected()
			GameEvents.emit_player_card_id(player)
			card_anim.play("select_anim")
			SupportData.reset_game_support()
			await card_anim.animation_finished
			GameEvents.emit_level_select_in()
