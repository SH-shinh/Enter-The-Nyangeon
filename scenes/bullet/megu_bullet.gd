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
	reset_physics_interpolation()
	super.idle_state()
	gpu_particles_2d.emitting = false
	gpu_particles_2d_2.emitting = false

func active_state():
	reset_physics_interpolation()
	if is_ready == false:
		return
	super.active_state()
	gpu_particles_2d.emitting = true
	gpu_particles_2d_2.emitting = true
	gpu_particles_2d.restart()
	gpu_particles_2d_2.restart()

func apply_penetrate_dealt():
	var cb: Callable = func(victim: Node, _actual_damage: float):
		if victim == null or not is_instance_valid(victim):
			return
		# 道具（SceneProp）没有 enemy_buff_manager/stats：跳过 buff，穿透按 PropStats 子节点取。
		var manager = victim.get("enemy_buff_manager")
		if manager != null and enemy_buff != null:
			manager.apply_buff(enemy_buff, value)
		var p := _ensure_player()
		if p != null:
			damage_data.knockback_direction = (victim.global_position - p.global_position).normalized()
		bulletSmoke(global_position)
		if can_block:
			var vstats = victim.get("stats")
			if vstats == null and victim.is_in_group("SceneProp"):
				vstats = victim.get_node_or_null("PropStats")
			penetrate -= 0 if vstats == null else maxi(0, int(vstats.penetrate_resis))
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
