extends EquipItem

# 紫人偶：受伤时以人偶为中心释放全屏冲击波脉冲，
# 对所有敌人施加一次 80 策反值的策反；冷却随叠加递减（最多 5 个）。

@onready var color_rect_2 = $CanvasLayer/ColorRect2
@onready var animation_player = $CanvasLayer/ColorRect2/AnimationPlayer
@onready var cd_timer = $CDTimer
@onready var yukari_doll_icon: PackedScene = preload("res://scenes/update_item/yukari_doll_icon.tscn")

const CONVERT_VALUE: int = 80
const BASE_COOLDOWN: float = 5.0
const MIN_COOLDOWN: float = 1.0

var game_camera: Node
var doll: Node

func _process(_delta):
	center_position()

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	game_camera = get_tree().get_first_node_in_group("PlayerCamera")
	cd_timer.wait_time = BASE_COOLDOWN
	spawn_doll()

func _setup():
	GameEvents.player_is_hurt.connect(_on_player_hurt)

func _apply_effect(quantity: int):
	cd_timer.wait_time = max(MIN_COOLDOWN, BASE_COOLDOWN - (quantity - 1))

func spawn_doll():
	if player == null:
		return
	var ins = yukari_doll_icon.instantiate()
	for i in get_tree().get_nodes_in_group("Follow"):
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
			ins.get_follow(i)
			i.follow_use = true
			doll = ins
			break

func _on_player_hurt(_player: Node):
	if cd_timer.time_left > 0:
		return
	cd_timer.start()
	SoundManager.play_sfx("EquipSounds8")
	animation_player.play("new_animation")
	apply_conversion()

func apply_conversion():
	for enemy in PoolManager.get_active_enemies():
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("apply_conversion_power"):
			enemy.apply_conversion_power(CONVERT_VALUE)

func center_position():
	if game_camera == null or player == null:
		return
	if not animation_player.is_playing():
		return
	var src: Node = doll if (doll != null and is_instance_valid(doll)) else player
	var cam_p = game_camera.get_camera_position()
	var screen_p = src.global_position - cam_p
	var n1 = (screen_p.x / 320.0) * 0.89
	var n2 = (screen_p.y / 180.0) * 0.5
	color_rect_2.material.set_shader_parameter("center", Vector2(0.5 + n1, 0.5 + n2))
