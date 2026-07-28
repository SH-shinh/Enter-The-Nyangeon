extends PanelContainer

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	focus_entered.connect(enter_anim)
	focus_exited.connect(exit_anim)

func enter_anim():
	animation_player.play("on_select")
	SoundManager.play_sfx("ButtonSounds2")

func exit_anim():
	animation_player.play("on_out")

func _input(event: InputEvent) -> void:
	if has_focus() and Input.is_action_just_pressed("ui_accept"):
		print("按钮按下")
