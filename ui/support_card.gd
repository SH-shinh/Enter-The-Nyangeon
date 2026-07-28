extends PanelContainer

@export var support_card: SupportCard

@onready var player_support: Sprite2D = $Node2D/TextureRect/player_support
@onready var weapon_name: Label = $Node2D/WeaponName
@onready var cost_bar: TextureProgressBar = $Node2D/cost_bar
@onready var ready_text: Label = $Node2D/ready
@onready var timer: Timer = $Timer

@onready var ready_anim: AnimationPlayer = $ready_anim

func _ready() -> void:
	GameEvents.support_ex_ready.connect(skill_ready_anim)
	GameEvents.support_ex_active.connect(skill_active)
	GameEvents.support_ex_end.connect(skill_end)
	GameEvents.player_hurt_hp.connect(hurt_anim)
	GameEvents.player_hurt_t_hp.connect(hurt_anim)
	SupportData.cost_changed.connect(update_bar)
	get_card()
	update_bar()

func get_card():
	if support_card != null:
		player_support.texture = support_card.character_sprite
		weapon_name.text = support_card.weapon_name

func update_bar():
	cost_bar.value = float(SupportData.now_cost) / float(SupportData.ex_cost)

func hurt_anim(_hurt_hp: int):
	face_anim(0)

func face_anim(type: int):
	timer.start()
	match type:
		0:
			var v = randi_range(0,1)
			if v == 1:
				player_support.frame = 1
			else:
				player_support.frame = 3
		1:
			var v = randi_range(0,1)
			if v == 1:
				player_support.frame = 0
			else:
				player_support.frame = 2

func ex_voice():
	if !support_card.ex_voice.is_empty():
		var n = randi_range(0, 2)
		SoundManager.play_support_voice(support_card.ex_voice[n])

func skill_ready_anim():
	ready_text.visible = true
	ready_text.text = "READY"
	ready_anim.play("ready_anim")

func skill_active():
	face_anim(1)
	ex_voice()
	ready_text.visible = true
	ready_text.text = "ACTIVE"
	ready_anim.play("active_anim")

func skill_end():
	ready_text.visible = false
	ready_anim.play("RESET")


func _on_timer_timeout() -> void:
	player_support.frame = 0
