extends Area2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var floating = preload("res://ui/floating_text.tscn")
@onready var timer: Timer = $Timer

var is_pick: bool = false
@export var pyroxenes_num: int = 1

func _ready():
	# 联机：把掉落广播给其它端（纯视觉；拾取增益已由 on_pyroxenes_gain 共享）
	ExtensionHooks.notify(ExtensionHooks.on_pickup_spawned, [self])

func _on_body_entered(body: Node2D) -> void:
	if is_pick == true:
		return
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Player"):
		add_pyroxenes()

func add_text(text: int):
	var ins = PoolManager.get_pool("floating_text")
	if ins == null or ins.is_idle == 0:
		ins = floating.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(ins)
	
	ins.global_position = global_position + (Vector2.UP * randf_range(30,45)) + (Vector2.RIGHT * randf_range(-25,25))
	ins.set_style(Color(1,1,1), 24)
	ins.play_anim(Color(1,1,1),Color(0.292, 0.838, 0.946))
	ins.start("+" + str(text))

func add_pyroxenes():
	if is_pick == true:
		return
	
	is_pick = true
	collision_shape_2d.set_deferred("disabled", true)
	timer.stop()
	self.z_index = 3
	pyroxenes_num = int(pyroxenes_num * PlayerData.level_reward)
	if PlayerData.game_mode.has("blitzkrieg") and !PlayerData.game_mode.has("endless"):
		pyroxenes_num *= 2
		PlayerData.player_pyroxenes += pyroxenes_num
		add_text(pyroxenes_num)
	else:
		PlayerData.player_pyroxenes += pyroxenes_num
		add_text(pyroxenes_num)
	GameEvents.emit_pyroxenes_pick_up()
	ExtensionHooks.notify(ExtensionHooks.on_pyroxenes_gain, [pyroxenes_num])
	animation_player.play("pick_up")
	SoundManager.play_sfx("CoinSounds")
	await animation_player.animation_finished
	queue_free()


func _on_timer_timeout() -> void:
	add_pyroxenes()
