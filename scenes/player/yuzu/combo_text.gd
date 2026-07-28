extends Node2D

@onready var label_2 = $Node2D/Label2
@onready var animation_player = $AnimationPlayer
@onready var animation_player_2 = $AnimationPlayer2
@onready var animation_player_3 = $AnimationPlayer3

func idle_state():
	animation_player.play("RESET")
	animation_player_3.play("RESET")
	self.visible = false

func play_max_anim():
	animation_player_3.play("max_anim")

func combo_num(num: String):
	if self.visible == false:
		self.visible = true
	if !animation_player.is_playing():
		animation_player.play("combo_loop")
	animation_player_2.play("combo_add_anim")
	label_2.text = num
