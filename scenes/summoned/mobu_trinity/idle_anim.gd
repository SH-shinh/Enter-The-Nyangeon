extends Node2D

const DEATH_GPU = preload("res://script/death_gpu.tscn")

@export var self_body: Node
@export var texture: Texture2D
@export var y_position = 15

var spawn_position: Vector2

func _ready():
	self_body.self_is_idle.connect(on_death_anim)
	spawn_position = Vector2.UP * y_position

func on_death_anim():
	
	var ins = DEATH_GPU.instantiate()
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	ins.global_position = self.global_position + spawn_position
	ins.gpu_particles_2d.texture = texture
	ins.animation_player.play("death")
	SoundManager.play_sfx("DeadSounds")
