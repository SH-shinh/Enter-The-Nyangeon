extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var option_button_box = $Node2D/option_button_box/VBoxContainer
@onready var menu_box = $menu_box


var on_option: bool = false
# 当前正在显示的页（menu_button_press 设置，关闭 option 时清空）。
# 关闭整个 option 不会对当前页调 menu_hide，故子页的 shown 不能代表“玩家正看着这一页”。
var _active_page: Control = null

func _ready():
	GameEvents.menu_button.connect(menu_button_press)
	ExtensionHooks.notify_named("populate_option_pages", [menu_box, option_button_box])
	menu_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	for page in menu_box.get_children():
		page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	$Node2D/return.focus_mode = Control.FOCUS_NONE
	# 系统文件拖放只在桌面原生主窗口触发（移动端/Web/headless 不会回调）。
	if OS.has_feature("pc") and DisplayServer.get_name() != "headless":
		get_window().files_dropped.connect(_on_files_dropped)

func on_option_selected():
	animation_player.play("option_in")
	on_option = true
	var tab := _current_tab()
	if tab != null:
		menu_button_press(tab.button_id)

func out_option_selected():
	button_close()
	SoundManager.play_sfx("UISounds2")
	animation_player.play("option_out")
	on_option = false
	_active_page = null

func button_open():
	menu_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	$Node2D/return.focus_mode = Control.FOCUS_ALL
	var buttons: Array = option_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_STOP
		i.focus_mode = Control.FOCUS_ALL
	var tab := _current_tab()
	if tab != null:
		tab.grab_focus()

func _current_tab() -> Control:
	var first: Control = null
	for tab in option_button_box.get_children():
		for page in menu_box.get_children():
			if tab.button_id != page.option_id:
				continue
			if first == null:
				first = tab
			if page.shown:
				return tab
	return first

func button_close():
	menu_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	$Node2D/return.focus_mode = Control.FOCUS_NONE
	var buttons: Array = option_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		i.focus_mode = Control.FOCUS_NONE

func menu_button_press(button_id: String):
	if not on_option:
		return

	var matched: bool = false
	var menus: Array = menu_box.get_children()
	_active_page = null

	for i in menus:
		if i.option_id == button_id:
			i.menu_show()
			_active_page = i
			matched = true

	if matched:
		botton_out_anim(button_id)


# 系统文件拖放：仅在 option 已展开、且有当前页时转发给实现了 handle_files_dropped 的页。
func _on_files_dropped(files: PackedStringArray) -> void:
	if not on_option or _active_page == null or not is_instance_valid(_active_page):
		return
	if _active_page.has_method("handle_files_dropped"):
		_active_page.call("handle_files_dropped", files)

func botton_out_anim(button_id: String):

	var buttons: Array = option_button_box.get_children()

	for i in buttons:
		if i.has_method("set_selected"):
			i.set_selected(i.button_id == button_id)
		elif i.button_id == button_id:
			i.on_show = true
		elif i.on_show:
			# 保留旧 Mod 自定义页签的显隐契约。
			i.on_show = false
			i.mouse_exitedd_anim()

	var menus: Array = menu_box.get_children()

	for i in menus:
		i.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if i.option_id == button_id else Control.FOCUS_BEHAVIOR_DISABLED
		if i.option_id != button_id:
			i.menu_hide()
