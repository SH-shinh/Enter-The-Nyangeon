extends Node

## 交互管理器：从组 "Interactable" 中选出玩家附近优先级最高的目标，
## 显示提示并在按下 use 时触发。不包含任何运动/物理逻辑。
##
## 提示分两种：
##  - 默认：屏幕空间纯文本 Label。
##  - 特殊：世界空间气泡 interact_prompt.tscn，仅当交互类实现了
##    wants_bubble_prompt() 且返回 true 时使用。
##
## 可交互对象需暴露：player_inside / enabled / interact_priority / prompt，
## 以及 interact(player)、set_highlight(bool)。

const BUBBLE_SCENE: PackedScene = preload("res://scenes/manager/interact_prompt.tscn")

@export var use_action: StringName = &"use"
@export var prompt_offset: Vector2 = Vector2(0, -52)

var player: Node = null
var current: Node = null

var _prompt_label: Label = null
var _bubble: Node2D = null
var _using_bubble: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.get_player.connect(_refresh_player)
	_refresh_player()
	_build_label()
	_build_bubble()

func _refresh_player() -> void:
	player = get_tree().get_first_node_in_group("Player")

func _unhandled_input(event: InputEvent) -> void:
	if current == null or not is_instance_valid(current):
		return
	if _is_blocked():
		return
	if event.is_action_pressed(use_action):
		current.interact(player)
		get_viewport().set_input_as_handled()
		return
	# 触屏：点按气泡（外扩 touch_margin）范围内即触发交互。
	if event is InputEventScreenTouch and event.pressed and _using_bubble:
		if _bubble != null and is_instance_valid(_bubble) and _bubble.has_method("get_touch_rect"):
			var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
			if _bubble.get_touch_rect().has_point(world):
				current.interact(player)
				get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_refresh_player()
		if player == null:
			return
	if _is_blocked():
		_set_current(null)
		return
	var best: Node = null
	var best_score := -INF
	for i in get_tree().get_nodes_in_group("Interactable"):
		if i == null or not is_instance_valid(i):
			continue
		if not i.get("player_inside") or not i.get("enabled"):
			continue
		var d: float = i.global_position.distance_to(player.global_position)
		var score: float = float(i.get("interact_priority")) * 100000.0 - d
		if score > best_score:
			best_score = score
			best = i
	_set_current(best)

func _process(_delta: float) -> void:
	if _using_bubble:
		if _bubble != null and current != null and is_instance_valid(current):
			_bubble.sync_position(current.global_position)
		return
	if _prompt_label == null or not _prompt_label.visible:
		return
	if current == null or not is_instance_valid(current) or player == null or not is_instance_valid(player):
		_hide_label()
		return
	var viewport := get_viewport()
	var screen_pos: Vector2 = viewport.get_canvas_transform() * (current.global_position + prompt_offset)
	_prompt_label.position = screen_pos - Vector2(200, 0)

func _set_current(next: Node) -> void:
	if current == next:
		return
	if current != null and is_instance_valid(current) and current.has_method("set_highlight"):
		current.set_highlight(false)
	current = next
	if current != null and is_instance_valid(current):
		if current.has_method("set_highlight"):
			current.set_highlight(true)
		_show_prompt(current)
	else:
		_hide_prompt()

func _show_prompt(target: Node) -> void:
	var text := str(target.get("prompt"))
	var wants_bubble: bool = _bubble != null and target.has_method("wants_bubble_prompt") and target.wants_bubble_prompt()
	_using_bubble = wants_bubble
	if wants_bubble:
		_hide_label()
		_bubble.show_prompt(text, target.global_position)
	else:
		_hide_bubble()
		_show_label(text)

func _hide_prompt() -> void:
	_using_bubble = false
	_hide_label()
	_hide_bubble()

func _is_blocked() -> bool:
	if get_tree().paused:
		return true
	if player != null and player.get("can_control") != null and player.can_control == false:
		return true
	return false

func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PromptLayer"
	layer.layer = 90
	add_child(layer)
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.visible = false
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.size = Vector2(400, 0)
	layer.add_child(_prompt_label)

func _build_bubble() -> void:
	if BUBBLE_SCENE == null:
		return
	_bubble = BUBBLE_SCENE.instantiate()
	_bubble.z_index = 100
	add_child(_bubble)

func _show_label(text: String) -> void:
	if _prompt_label == null or text.is_empty():
		_hide_label()
		return
	_prompt_label.text = "[use] " + text
	_prompt_label.visible = true

func _hide_label() -> void:
	if _prompt_label != null:
		_prompt_label.visible = false

func _hide_bubble() -> void:
	if _bubble != null and _bubble.has_method("hide_prompt"):
		_bubble.hide_prompt()
