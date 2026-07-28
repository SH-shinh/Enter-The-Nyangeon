extends Area2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var equip_damage: int
var equip_knockback: int
var is_critical: bool = false
var is_equip_shoot: bool = false

var is_idle: int = 1

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	collision_shape_2d.disabled = true

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("atk_anim")
	gpu_particles_2d.restart()

func play_sfx():
	SoundManager.play_sfx("EquipSounds4")

func _on_body_entered(body):
	
	if body.is_in_group("Enemy"):
		
		body.hurt_damage = equip_damage
		body.hurt_knockback = 0
		body.hurt_direction = Vector2.ZERO
		
		body.emit_signal("is_hurt")
