extends Node2D

## 语言选择器（主菜单 / 暂停页共用）：语言列表来自 ModManager.get_languages()
## （内置 4 种 + mod 经 ModAPI.register_language 注册/覆盖），支持 display_font 指定显示名字体。
## 桌面用 OptionButton 原生下拉；触屏点按开 touch_menu 自定义列表。

@onready var option_button: OptionButton = $OptionButton
@onready var touch_menu: Node2D = $touch_menu
@onready var touch_panel: PanelContainer = $touch_menu/PanelContainer
@onready var touch_list: VBoxContainer = $touch_menu/PanelContainer/VBoxContainer

const ROW_FALLBACK_FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")

var on_touch: bool = false
var _langs: Array = []

func _ready() -> void:
	_rebuild()
	ModManager.languages_changed.connect(_rebuild)
	option_button.gui_input.connect(touch_input)
	GameEvents.player_card_touch.connect(close_touch_menu)

func touch_input(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		option_button.accept_event()
		SoundManager.play_sfx("ButtonSounds")
		open_touch_menu()

func open_touch_menu():
	on_touch = true
	touch_menu.visible = true

func close_touch_menu():
	if on_touch == true:
		on_touch = false
		touch_menu.visible = false

# 从注册表重建下拉项与触摸列表（语言变化时也会被调）。
func _rebuild() -> void:
	_langs = ModManager.get_languages()
	option_button.clear()
	for i in _langs.size():
		option_button.add_item(str(_langs[i].get("display_name", _langs[i].get("locale", ""))), i)
	_rebuild_touch_list()
	_set_button(Game.game_language)

func _rebuild_touch_list() -> void:
	for c in touch_list.get_children():
		touch_list.remove_child(c)
		c.queue_free()
	for lang in _langs:
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 20)
		var lbl := Label.new()
		lbl.text = str(lang.get("display_name", lang.get("locale", "")))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", _display_font(lang, ROW_FALLBACK_FONT))
		lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl)
		row.gui_input.connect(_on_row_gui_input.bind(str(lang.get("locale", ""))))
		touch_list.add_child(row)
	_fit_touch_panel()

func _fit_touch_panel() -> void:
	touch_panel.reset_size()
	touch_panel.size.x = 103

func _display_font(lang: Dictionary, fallback: Font) -> Font:
	var f = lang.get("display_font", null)
	if f is Font:
		return f
	if f is String and f != "":
		var r = load(f)
		if r is Font:
			return r
	return fallback

# 应用某语言的按钮显示名字体（OptionButton 选中文字 + 原生下拉 PopupMenu，best-effort）。
func _apply_display_font(lang: Dictionary) -> void:
	var has := false
	var f := _display_font(lang, null)
	if f != null:
		has = true
		option_button.add_theme_font_override("font", f)
	else:
		option_button.remove_theme_font_override("font")
	var pop := option_button.get_popup()
	if pop != null:
		if has:
			pop.add_theme_font_override("font", f)
		else:
			pop.remove_theme_font_override("font")

func _index_of(locale: String) -> int:
	for i in _langs.size():
		if str(_langs[i].get("locale", "")) == locale:
			return i
	return 0 if not _langs.is_empty() else -1

func _set_button(langue: String):
	var idx := _index_of(langue)
	if idx >= 0:
		option_button.selected = idx
		_apply_display_font(_langs[idx])

func _apply_locale(locale: String) -> void:
	if locale == "":
		return
	Game.game_language = locale
	TranslationServer.set_locale(locale)
	Game.save_config()
	_set_button(locale)

func _on_option_button_item_selected(index: int) -> void:
	if index < 0 or index >= _langs.size():
		return
	_apply_locale(str(_langs[index].get("locale", "")))

func _on_row_gui_input(event: InputEvent, locale: String) -> void:
	if event as InputEventScreenTouch and event.pressed:
		option_button.accept_event()
		_apply_locale(locale)
		close_touch_menu()

func _on_option_button_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
