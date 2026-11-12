extends Node2D
## Chihiro 近战：按踢击键「掏出控制器按一下」（动画参考 Kasumi 的掏道具结构），
## 静电由 PS 本体释放；控制器只做表现，不抛出、不结算。

@export var player: Node
@export var ps_node: Node

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var timer: Timer = $Timer
@onready var node_2d = $"../Graphics/Node2D"

func _physics_process(delta):
	node_2d.position.y = player.sprite_2d.position.y + 17

func kick_start() -> void:
	if timer.time_left > 0:
		return
	if player == null or not is_instance_valid(player):
		return
	# 静电由玩家本体释放；控制器只做手部动画
	if ps_node != null and ps_node.has_method("release_static"):
		ps_node.call("release_static", player.global_position)
	animation_player.play("melee_anim")
	timer.start()
	SoundManager.play_sfx("ButtonSounds")
	ExtensionHooks.notify_named("on_player_melee", [player, "melee_anim"])
