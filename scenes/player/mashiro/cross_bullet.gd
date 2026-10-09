extends HitBox

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var equip_damage: int
var equip_knockback: int
var is_critical: bool = false
var is_equip_shoot: bool = false

var is_idle: int = 1

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	collision_shape_2d.set_deferred("disabled", true)

func active_state():
	is_idle = 0
	if damage_data != null:
		damage_data.source_node = get_path()
	self.visible = true
	animation_player.play("atk_anim")
	gpu_particles_2d.restart()

func play_sfx():
	SoundManager.play_sfx("EquipSounds4")
