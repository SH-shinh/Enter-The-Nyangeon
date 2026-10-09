extends PlayerBullet

@warning_ignore("unused_signal")
signal enemy_body_get(body: Node)

@export var enemy_buff: Buff

@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2

var value: Array = [1,1,1]

var can_block: bool = true

func _ready():
	super._ready()

func idle_state():
	super.idle_state()
	gpu_particles_2d.emitting = false
	gpu_particles_2d_2.emitting = false

func active_state():
	if is_ready == false:
		return
	super.active_state()
	gpu_particles_2d.emitting = true
	gpu_particles_2d_2.emitting = true
	gpu_particles_2d.restart()
	gpu_particles_2d_2.restart()

func apply_penetrate_dealt():
	var cb: Callable = func(victim: Node, _actual_damage: float):
		victim.enemy_buff_manager.apply_buff(enemy_buff, value)
		damage_data.knockback_direction = (victim.global_position - player.global_position).normalized()
		bulletSmoke(global_position)
		if can_block:
			penetrate -= victim.stats.penetrate_resis
			if penetrate <= 0:
				if collision_num > 0:
					direction = Vector2.RIGHT.rotated(global_rotation + randf_range(0.7, 1.3) * PI)
					velocity = direction * speed
					rotation = velocity.angle()
					collision_num -= 1
				else:
					GameEvents.emit_player_bullet_free_position(self.global_position)
					idle_state()
	damage_data.on_damage_dealt.append(cb)
