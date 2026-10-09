extends PanelContainer

# 像素风格开关（复刻 game_option 的 FullScreen/Shake/VSync 开关视觉）。
# 供 MOD 列表行等处复用；自身处理 hover / 点击 / 触屏，发出 toggled(on)。

signal toggled(on: bool)

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var on: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	gui_input.connect(_on_gui_input)
	if on:
		animation_player.play("selected")
		animation_player.seek(animation_player.current_animation_length, true)


func set_on(value: bool, animate: bool = true) -> void:
	on = value
	var anim := "selected" if on else "full_out"
	animation_player.play(anim)
	if not animate:
		animation_player.seek(animation_player.current_animation_length, true)


func _on_hover() -> void:
	animation_player.play("selected_out" if on else "full_on")


func _on_unhover() -> void:
	animation_player.play("selected" if on else "full_out")


func _on_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event.is_action_pressed("shoot"):
		pressed = true
	if not pressed:
		return
	on = not on
	animation_player.play("selected" if on else "full_out")
	toggled.emit(on)
