extends EquipItem

@onready var color_rect_2 = $CanvasLayer/ColorRect2
@onready var animation_player = $CanvasLayer/ColorRect2/AnimationPlayer
@onready var area_2d = $Area2D
@onready var cd_timer = $CDTimer

# 冲击波清除半径（对齐场景 Area2D 的 CircleShape2D radius=120）
@export var clear_radius: float = 120.0

var game_camera: Node

func _process(delta):
	center_position()

func _on_equip():
	GameEvents.player_is_hurt.connect(clear_enemy_bullet)
	game_camera = get_tree().get_first_node_in_group("PlayerCamera")
	player = get_tree().get_first_node_in_group("Player")
	area_2d.area_entered.connect(_on_area_2d_area_entered)

func clear_enemy_bullet(player: Node):

	if animation_player.is_playing() and cd_timer.time_left <= 0:
		return
	cd_timer.start()
	SoundManager.play_sfx("EquipSounds2")
	animation_player.play("new_animation")
	# 联机：通知 mod 做 host 权威半径清除（未装 mod 时为空 Callable，无副作用）
	ExtensionHooks.notify(ExtensionHooks.on_enemy_bullet_clear, [area_2d.global_position, clear_radius])

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

func _on_area_2d_area_entered(body: Area2D):
	if body.is_in_group("EnemyBullet") and body.has_method("bullet_clear"):
		body.bullet_clear()
		SoundManager.play_sfx("EquipSounds1")
