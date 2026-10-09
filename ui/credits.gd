extends Control

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var scroll_container: ScrollContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer
@onready var list_box: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/ListBox

@export var font_type: Font
@export var auto_scroll_speed: float = 20.0
@export var auto_scroll_return_speed: float = 120.0
@export var auto_scroll_pause: float = 1.0
@export var manual_resume_delay: float = 1.5

const SECTIONS: Array = [
	{ "lang": " ", "members": [] },
	{ "lang": "credits_production", "members": ["SH\nX: https://x.com/shinsssh\nitch: https://shinh.itch.io/enter-the-nyangeon\nBiliBili: https://space.bilibili.com/488279"] },
	{ "lang": "credits_music", "members": ["NEXON - BlueArchive"] },
	{ "lang": " ", "members": [] },
	{ "lang": "credits_special_thanks", "members": [], "color": Color(0.9, 0.84, 0.4) },
	{ "lang": "coop_special_thanks", "members": ["荻某人\nBiliBili: https://space.bilibili.com/404380192"] },
	{ "lang": "Português", "members": ["Filipe\nX: https://x.com/_Filipe1704_"] },
	{ "lang": "Vietnamese", "members": ["KingLancer2204"] },
	{ "lang": " ", "members": [] },
	{ "lang": "thank_you_for_playing", "members": [], "color": Color(0.9, 0.44, 0.5) },
]

const HEADER_FONT_SIZE: int = 14
const MEMBER_FONT_SIZE: int = 12
const HEADER_COLOR: Color = Color(0.4038, 0.672602, 0.932866, 1)
const HEADER_OUTLINE_SIZE: int = 10
const HEADER_OUTLINE_COLOR: Color = Color(0.145, 0.145, 0.145)

enum ScrollPhase { DOWN, UP }

var is_show: bool = false
var _phase: int = ScrollPhase.DOWN
var _frac: float = 0.0
var _pause_left: float = 0.0

func _ready() -> void:
	set_process(false)
	scroll_container.gui_input.connect(_on_scroll_input)
	build_list()
	hide()

func _process(delta: float) -> void:
	if is_show == false:
		return
	var vbar := scroll_container.get_v_scroll_bar()
	var max_scroll := int(vbar.max_value - vbar.page)
	if max_scroll <= 0:
		return
	if scroll_container.get("isDrag") == true:
		_pause_left = manual_resume_delay
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	if _phase == ScrollPhase.DOWN:
		_frac += auto_scroll_speed * delta
		var step := int(_frac)
		if step > 0:
			_frac -= step
			scroll_container.scroll_vertical += step
		if scroll_container.scroll_vertical >= max_scroll:
			scroll_container.scroll_vertical = max_scroll
			_phase = ScrollPhase.UP
			_frac = 0.0
			_pause_left = auto_scroll_pause
	else:
		_frac += auto_scroll_return_speed * delta
		var step := int(_frac)
		if step > 0:
			_frac -= step
			scroll_container.scroll_vertical -= step
		if scroll_container.scroll_vertical <= 0:
			scroll_container.scroll_vertical = 0
			_phase = ScrollPhase.DOWN
			_frac = 0.0
			_pause_left = auto_scroll_pause

func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_pause_left = manual_resume_delay

func _reset_scroll() -> void:
	scroll_container.scroll_vertical = 0
	_phase = ScrollPhase.DOWN
	_frac = 0.0
	_pause_left = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		build_list()

func build_list() -> void:
	for n in list_box.get_children():
		list_box.remove_child(n)
		n.queue_free()
	for section in SECTIONS:
		var lang: String = section.get("lang", "")
		if lang != "":
			var header := Label.new()
			header.text = lang
			header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			header.add_theme_font_override("font", font_type)
			header.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
			header.add_theme_color_override("font_color", section.get("color", HEADER_COLOR))
			header.add_theme_constant_override("outline_size", HEADER_OUTLINE_SIZE)
			header.add_theme_color_override("font_outline_color", HEADER_OUTLINE_COLOR)
			list_box.add_child(header)
		for member in section.get("members", []):
			var member_label := Label.new()
			member_label.text = member
			member_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			member_label.add_theme_font_override("font", font_type)
			member_label.add_theme_font_size_override("font_size", MEMBER_FONT_SIZE)
			list_box.add_child(member_label)
	_reset_scroll()

func show_credits() -> void:
	is_show = true
	show()
	_reset_scroll()
	set_process(true)
	animation_player.play("enter_anim")

func hide_credits() -> void:
	if is_show == false:
		return
	is_show = false
	set_process(false)
	animation_player.play_backwards("enter_anim")
	await animation_player.animation_finished
	if is_show == false:
		hide()

func _unhandled_input(event: InputEvent) -> void:
	if is_show == true and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		hide_credits()
