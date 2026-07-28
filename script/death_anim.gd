extends Node2D

const DEATH_GPU = preload("res://script/death_gpu.tscn")

@export var stats: EnemyStats
@export var y_position = 15

var sprite: String
var parent_node
var spawn_position: Vector2
var texture

func _ready():
	stats.is_dead.connect(on_death_anim)
	parent_node = get_parent()
	sprite = parent_node.icon
	spawn_position = Vector2.UP * y_position
	parent_node.is_dead.connect(on_death_anim)
	texture = load("res://sprites/enemies/" + sprite + ".png")
	

func on_death_anim():
	
	var ins = DEATH_GPU.instantiate()
	get_tree().get_first_node_in_group("EnemiesRoot").add_child(ins)
	ins.global_position = self.global_position + spawn_position
	ins.gpu_particles_2d.texture = texture
	ins.animation_player.play("death")
	SoundManager.play_sfx("DeadSounds")
