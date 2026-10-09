extends Button

# 分支按钮动画：
# - 桌面鼠标：悬停播 hover_anim，移出反向播放
# - 触摸：不播悬停，按下直接播 press_anim
# - 点击动画播完后若仍悬停，回到悬停态
# - 消费输入，避免点击冒泡给 player_card

@onready var anim: AnimationPlayer = $AnimationPlayer

var _hovered: bool = false
var _touch_input: bool = false


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)
	button_down.connect(_on_press)
	anim.animation_finished.connect(_on_anim_finished)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_input = true
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_touch_input = false


func _on_hover_in() -> void:
	_hovered = true
	if _touch_input:
		return
	anim.play("hover_anim")
	SoundManager.play_sfx("ButtonSounds2")


func _on_hover_out() -> void:
	_hovered = false
	if _touch_input:
		return
	anim.play_backwards("hover_anim")


func _on_press() -> void:
	anim.play("press_anim")
	SoundManager.play_sfx("ButtonSounds")


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == "press_anim" and _hovered and not _touch_input:
		anim.play("hover_anim")
		
