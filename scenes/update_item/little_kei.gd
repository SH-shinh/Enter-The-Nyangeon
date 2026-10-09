extends EquipItem

var kei_velocity: float = 0.003
var dir: Vector2
var player: Node

@onready var marker_2d = $Marker2D
@onready var kei = $Path2D/PathFollow2D/Kei
@onready var area_2d = $Path2D/PathFollow2D/Kei/Area2D
@onready var animation_player_2 = $Path2D/PathFollow2D/Kei/Area2D/AnimatedSprite2D/AnimationPlayer2
@onready var animated_sprite_2d = $Path2D/PathFollow2D/Kei/Area2D/AnimatedSprite2D/AnimationPlayer
@onready var path_follow_2d: PathFollow2D = $Path2D/PathFollow2D
@onready var sprite_2d: Sprite2D = $Path2D/PathFollow2D/Kei/Sprite2D

func _physics_process(delta):
	path_follow_2d.progress_ratio = wrapf(path_follow_2d.progress_ratio + kei_velocity, 0, 1)

func _on_equip():
	kei_velocity = 0.003
	area_2d.scale = Vector2(1, 1)

func _setup():
	player = get_tree().get_first_node_in_group("Player")
	area_2d.area_entered.connect(_on_area_2d_area_entered)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	if kei_velocity < 0.02:
		kei_velocity *= 1.2
	area_2d.scale *= 1.1

func _on_timer_timeout():
	var num = randf_range(-1, 1)
	if num > 0:
		sprite_2d.scale.x = 1
	elif num < 0:
		sprite_2d.scale.x = -1

func _on_area_2d_area_entered(body:Area2D):
	if body.is_in_group("EnemyBullet") and body.has_method("bullet_clear"):
		body.bullet_clear()
		animation_player_2.play("new_animation")
		SoundManager.play_sfx("EquipSounds1")
		GameEvents.emit_player_is_hurt(player)
