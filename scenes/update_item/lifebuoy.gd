extends Node2D

@onready var color_rect_2 = $CanvasLayer/ColorRect2
@onready var animation_player = $CanvasLayer/ColorRect2/AnimationPlayer
@onready var area_2d = $Area2D
@onready var cd_timer = $CDTimer

var num: int

var game_camera: Node
var player: Node

func _ready():
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_is_hurt.connect(clear_enemy_bullet)
	game_camera = get_tree().get_first_node_in_group("PlayerCamera")
	player = get_tree().get_first_node_in_group("Player")

func _process(delta):
	center_position()
	
func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "lifebuoy":
		return
	if current_upgrade["lifebuoy"]["quantity"] == 1:
		return
	num = current_upgrade["lifebuoy"]["quantity"]

func clear_enemy_bullet(player: Node):
	
	if animation_player.is_playing() and cd_timer.time_left <= 0:
		return
	cd_timer.start()
	SoundManager.play_sfx("EquipSounds2")
	animation_player.play("new_animation")

func center_position():
	if animation_player.is_playing():
		var p1 = game_camera.get_camera_position()
		var player_p = player.global_position
		var screen_p = player_p - p1
		var t1 = screen_p.x / 320
		var t2 = screen_p.y / 180
		var n1 = t1 * 0.89
		var n2 = t2 * 0.5
		color_rect_2.material.set_shader_parameter("center", Vector2(0.5 + n1, 0.5 + n2))


func _on_area_2d_body_entered(body):
	if body.is_in_group("EnemyBullet"):
		body.now_penetrate -= 1000
		SoundManager.play_sfx("EquipSounds1")
