extends Node2D

@export var talk_work_in: Array[TalkFormwork]
@export var talk_normal: Array[TalkFormwork]
@export var talk_surprise: Array[TalkFormwork]
@export var talk_head: Array[TalkFormwork]
@export var talk_lack: Array[TalkFormwork]

@export var text_color: Color
@export var outline_color: Color

@export var voice_name: String

@onready var sprite: Sprite2D = $Sprite
@onready var talk_text: PackedScene = preload("res://ui/ark_of_Shittim/talk_text.tscn")
@onready var text_root: Node2D = $TextRoot
@onready var talk_anim: AnimationPlayer = $TalkAnim
@onready var change_anim: AnimationPlayer = $ChangeAnim
@onready var cloth_change: Node2D = $ClothChange

@onready var talk_touch: Panel = $TouchArea/TalkTouch
@onready var head_touch: Panel = $TouchArea/HeadTouch
@onready var breast_touch: Panel = $TouchArea/BreastTouch

var voice_playing: bool = false
var normal_index: int = 0
var surprise_touch_num: int = 0


func _ready() -> void:
	talk_touch.gui_input.connect(talk_touch_voice)
	breast_touch.gui_input.connect(breast_touch_voice)
	head_touch.gui_input.connect(head_touch_voice)
	GameEvents.pyroxenes_not_enough.connect(lack_talk)
	get_now_clothes()

func get_now_clothes():
	var card_load = load("res://resources/clothes/" + voice_name + "/" + PlayerData.now_clothes[voice_name] + ".tres")
	sprite.texture = card_load.sprite

func reset_state():
	sprite.frame = 0

func worl_in_voice():
	var rand_i = randi_range(0, talk_work_in.size() - 1)
	play_talk_anim(talk_work_in[rand_i])

func breast_touch_voice(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed and voice_playing == false:
		if surprise_touch_num == 9:
			play_talk_anim(talk_surprise[3])
		else:
			var rand_i = randi_range(0, talk_surprise.size() - 2)
			play_talk_anim(talk_surprise[rand_i])
			talk_anim.play("surprise_anim")
		surprise_touch_num = wrapi(surprise_touch_num + 1, 0, 10)
	
	if event.is_action_pressed("shoot") and voice_playing == false:
		if surprise_touch_num == 9:
			play_talk_anim(talk_surprise[3])
		else:
			var rand_i = randi_range(0, talk_surprise.size() - 2)
			play_talk_anim(talk_surprise[rand_i])
			talk_anim.play("surprise_anim")
		surprise_touch_num = wrapi(surprise_touch_num + 1, 0, 10)
		

func head_touch_voice(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed and voice_playing == false:
		var rand_i = randi_range(0, talk_head.size() - 1)
		play_talk_anim(talk_head[rand_i])
		talk_anim.play("nod_anim")
	
	if event.is_action_pressed("shoot") and voice_playing == false:
		var rand_i = randi_range(0, talk_head.size() - 1)
		play_talk_anim(talk_head[rand_i])
		talk_anim.play("nod_anim")

func talk_touch_voice(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed and voice_playing == false:
		play_talk_anim(talk_normal[normal_index])
		normal_index = wrapi(normal_index + 1, 0, talk_normal.size())
	
	if event.is_action_pressed("shoot") and voice_playing == false:
		play_talk_anim(talk_normal[normal_index])
		normal_index = wrapi(normal_index + 1, 0, talk_normal.size())
		

func lack_talk(event_name:String):
	if event_name == voice_name:
		var rand_i = randi_range(0, talk_lack.size() - 1)
		play_talk_anim(talk_lack[rand_i])

func play_talk_anim(talk_card: TalkFormwork):
	if voice_playing == false:
		voice_playing = true
		sprite.frame = talk_card.sprite_num
		if talk_card.voice_num != "":
			SoundManager.play_talk(talk_card.voice_name, talk_card.voice_num)
		
		var ins = talk_text.instantiate()
		text_root.add_child(ins)
		if talk_card.talk_text != "":
			ins.talk_in(talk_card.talk_text, text_color, outline_color)
		
		if talk_card.voice_time > 0:
			await get_tree().create_timer(talk_card.voice_time).timeout
		else:
			if talk_card.voice_num != "":
				await SoundManager.talk.get_node(talk_card.voice_name).get_node(talk_card.voice_num).finished
			else:
				await get_tree().create_timer(1.5).timeout
		ins.talk_out()
		reset_state()
		voice_playing = false

func change_clothes(cloth_card: ClothesCard):
	cloth_change.close_button()
	change_anim.play("change_anim")
	await get_tree().create_timer(0.26).timeout
	sprite.texture = cloth_card.sprite
	await change_anim.animation_finished
	cloth_change.open_button()
