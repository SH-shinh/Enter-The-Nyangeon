extends Node2D

var shoot: bool = true

@onready var particles_1 = preload("res://script/explosion_particles.tscn")
@onready var particles_2 = preload("res://script/explosion_smoke_particles.tscn")
@onready var layer_1 = $Layer1
@onready var layer_2 = $Layer2
@onready var layer_3 = $Layer3
@onready var animation_player = $AnimationPlayer

@onready var gpu_particles_2d_2 = $GPUParticles2D2
@onready var gpu_particles_2d_4 = $GPUParticles2D4
@onready var gpu_particles_2d_3 = $GPUParticles2D3


var is_idle: int = 1


func _ready():
	PoolManager.add_pool("big_explosion",self)

func idle_state():
	is_idle = 1
	shoot = true
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("explosion")
	gpu_particles_2d_2.restart()
	gpu_particles_2d_3.restart()
	gpu_particles_2d_4.restart()

func shoot_particles():
	
	if shoot == false:
		return
	if not PoolManager.fx_allowed(&"explosion"):
		return
	
	for i in randi_range(1, 2):
		var c1 = PoolManager.get_pool("explosion_particles")
		if c1 == null or c1.is_idle == 0:
			c1 = particles_1.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(c1)
		c1.global_position = self.global_position
		c1.velocity.x = randi_range(200, 450)
		c1.velocity.y = randi_range(-600, -350)
		c1.active_state()
		
	for i in randi_range(1, 2):
		var c1 = PoolManager.get_pool("explosion_particles")
		if c1 == null or c1.is_idle == 0:
			c1 = particles_1.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(c1)
		c1.global_position = self.global_position
		c1.velocity.x = randi_range(-450, -200)
		c1.velocity.y = randi_range(-600, -350)
		c1.active_state()
	for i in randi_range(1, 2):
		var c1 = PoolManager.get_pool("explosion_particles")
		if c1 == null or c1.is_idle == 0:
			c1 = particles_1.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(c1)
		c1.global_position = self.global_position
		c1.velocity.x = randi_range(-100, 100)
		c1.velocity.y = randi_range(-600, -350)
		c1.active_state()
	for i in 1:
		var c2 = PoolManager.get_pool("explosion_smoke_particles")
		if c2 == null or c2.is_idle == 0:
			c2 = particles_2.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(c2)
		c2.global_position = self.global_position
		c2.velocity.x = randi_range(200, 450)
		c2.velocity.y = randi_range(-500, -350)
		c2.active_state()
	for i in 1:
		var c2 = PoolManager.get_pool("explosion_smoke_particles")
		if c2 == null or c2.is_idle == 0:
			c2 = particles_2.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(c2)
		c2.global_position = self.global_position
		c2.velocity.x = randi_range(-450, -200)
		c2.velocity.y = randi_range(-500, -350)
		c2.active_state()
	for i in 1:
		var c2 = PoolManager.get_pool("explosion_smoke_particles")
		if c2 == null or c2.is_idle == 0:
			c2 = particles_2.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(c2)
		c2.global_position = self.global_position
		c2.velocity.x = randi_range(-100, 100)
		c2.velocity.y = randi_range(-550, -350)
		c2.active_state()
