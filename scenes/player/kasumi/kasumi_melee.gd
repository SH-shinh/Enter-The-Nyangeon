extends Node2D

@export var player: Node
@export var ps_node: Node
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var drill_ins: PackedScene = preload("res://scenes/player/kasumi/kasumi_drill.tscn")
@onready var timer: Timer = $Timer
@onready var marker_2d: Marker2D = $Marker2D
@onready var node_2d: Node2D = $"../GraphicsGun/Node2D"

var kasumi_drill: Node = null

func _physics_process(delta: float) -> void:
	node_2d.position.y = player.sprite_2d.position.y + 17

func kick_start():
	if timer.time_left <= 0:
		if kasumi_drill == null:
			add_drill()
		
		if kasumi_drill != null:
			kasumi_drill.idle_state()
			kasumi_drill.now_t = ps_node.now_t
			kasumi_drill.global_position = marker_2d.global_position
			kasumi_drill.player_position = player.global_position
			kasumi_drill.scale_x = player.graphics.scale.x
			kasumi_drill.melee_cd = ps_node.t_cd
			kasumi_drill.player_explosion_damage = ps_node.e_damage
			kasumi_drill.max_layer = ps_node.buff_layer
			kasumi_drill.active_state()
			# 联机（M5 角色事件）：把钻头近战广播给其它端做纯视觉回放
			player.broadcast_character_event(&"kasumi_drill", {
				"pos": marker_2d.global_position,
				"scale_x": player.graphics.scale.x,
				"now_t": ps_node.now_t,
				"lv": 0,
				"dur": 0.7,
			})
			animation_player.play("melee_anim")
			SoundManager.play_sfx("ButtonSounds")
			timer.start()

func add_drill():
	var drill = drill_ins.instantiate()
	get_tree().get_first_node_in_group("PlayerRoot").add_child(drill)
	kasumi_drill = drill
	kasumi_drill.player = player
