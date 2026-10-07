extends CanvasLayer

## 房主「难度选择」面板（全员就绪后弹出）。
## 复用本体 level_button（含关卡颜色/动画）与 gamemode_button（游戏模式），
## 关卡列表来自 CoopNet.get_level_catalog()（数据驱动，便于 Mod 扩展）。
## 选关后由 level_button 触发 GameEvents.change_scene → CoopNet 的 change_scene gate 统一开战。
## ESC = 房主放弃选择 → 全员取消就绪（CoopNet.cancel_select）。
## 静态布局在 coop_difficulty.tscn；本脚本按目录动态实例化关卡按钮。

signal level_is_selected
signal player_selected

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const LEVEL_BUTTON := preload("res://ui/level_button.tscn")
const DEFAULT_PLAYER_SCENE := "res://scenes/player/momoi/momoi.tscn"

@onready var _level_box: VBoxContainer = %LevelBox
@onready var _anim: AnimationPlayer = $AnimationPlayer

var player: String = ""


func _ready() -> void:
	var coop = CoopNetScript.instance
	if coop != null:
		if str(coop.local_player_scene_path) != "":
			player = str(coop.local_player_scene_path)
		else:
			player = DEFAULT_PLAYER_SCENE
	_populate_levels()
	# 激活关卡按钮（level_button 初始 mouse_filter=IGNORE，靠 player_selected → open_mouse）
	player_selected.emit()
	if _anim != null and _anim.has_animation("show_anim"):
		_anim.play("show_anim")


# 关闭时倒放进场动画（由 CoopFlow 调用，随后延时释放本层）
func play_hide() -> void:
	if _anim != null and _anim.has_animation("show_anim"):
		_anim.play_backwards("show_anim")


func _populate_levels() -> void:
	var coop = CoopNetScript.instance
	var catalog: Array = coop.get_level_catalog() if coop != null else []
	for entry in catalog:
		var lv = entry.get("level")
		if lv == null:
			continue
		var ins = LEVEL_BUTTON.instantiate()
		ins.level = lv
		ins.path = str(entry.get("scene_path", "res://scenes/main/main.tscn"))
		ins.level_select = self
		_level_box.add_child(ins)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		var coop = CoopNetScript.instance
		if coop != null:
			coop.call("cancel_select")
		get_viewport().set_input_as_handled()
