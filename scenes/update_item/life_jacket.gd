extends Node2D

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var cd_timer = $CDTimer
@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
@onready var animation_player = $Node2D/AnimationPlayer
@onready var node_2d_2 = $Node2D2
@onready var animation_player_2 = $Node2D2/AnimationPlayer

var value: Array =[]
var num: int
var player: Node

func _ready():
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	player = get_tree().get_first_node_in_group("Player")
	player.stats.hurt_invalid_changed.connect(player_get_hurt)
	cd_timer.timeout.connect(add_player_hurt_invalid)
	GameEvents.round_start.connect(add_player_hurt_invalid)
	value = [buff_layer, buff_value, buff_erase_timer]
	add_player_hurt_invalid()

func _process(delta):
	if node_2d_2.visible == true:
		node_2d_2.position = player.sprite_2d.position

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "life_jacket":
		return
	if current_upgrade["life_jacket"]["quantity"] == 1:
		return
	num = current_upgrade["life_jacket"]["quantity"]

func add_player_hurt_invalid():
	node_2d_2.visible = true
	animation_player_2.play("new_animation")
	player.player_buff_manager.apply_buff(player_buff, value)

func player_get_hurt():
	node_2d_2.visible = false
	SoundManager.play_sfx("EquipSounds2")
	animation_player.play("new_animation")
	cd_timer.start()


func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_knockback = player.stats.bullet_knockback + 250
		body.hurt_direction = hit_direction
		body.emit_signal("is_hurt")
