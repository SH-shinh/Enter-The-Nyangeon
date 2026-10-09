extends Node2D

@export var player: Node
@export var sheild: Node
@export var player_ps: Node
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var timer: Timer = $Timer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var hit_box = $HitBox

var charge_time: int = 2
var now_time: int = 0
var reset_time: int = 0

var melee_index: int = 0
var can_comboo: bool = true
var enhancement_melee: bool = false

var melee_damage: int = 20

var x_movement: float = 0
var y_movement: float = 0

var body_group: Array[Node]

func _ready() -> void:
	GameEvents.global_time_count.connect(time_count)
	GameEvents.round_start.connect(control_reset)
	GameEvents.round_end.connect(control_reset)
	timer.timeout.connect(reset_melee_index_time)
	hit_box.area_entered.connect(_on_hit_box_entered)

func reset_melee_index_time():
	animation_player.play("RESET")
	enhancement_melee = false
	player_ps.ammo_end = false
	player.can_jump = true
	reset_time = 6

func melee_shake():
	GameEvents.emit_shake_screen( 3, 35, 0.025 )

func control_reset():
	if player.can_control == false:
		player.can_control = true

func time_count():
	if now_time > 0:
		now_time -= 1
		if now_time <= 0:
			player.can_control = true
			player.velocity = Vector2.ZERO
	
	if reset_time > 0:
		reset_time -= 1
		if reset_time <= 0:
			melee_can_comboo()
			melee_index = 0
	

func melee_can_comboo():
	can_comboo = true

func melee_anim_play(anim_time: float, charge_speed: int, anim_name: String, next_index: int):
	reset_time = 0
	SoundManager.play_sfx("Swing1")
	can_comboo = false
	timer.wait_time = anim_time
	timer.start()
	now_time = charge_time
	player.can_control = false
	player.can_jump = false
	if Game.control_mode != 1:
		player.velocity = Vector2.RIGHT.rotated(self.rotation) * ( player.stats.MAX_SPEED + charge_speed )
	else:
		x_movement = Input.get_axis("move_left", "move_right")
		y_movement = Input.get_axis("move_up", "move_down")
		if x_movement!= 0 and y_movement != 0:
			player.velocity = Vector2(x_movement, y_movement) * ( player.stats.MAX_SPEED + charge_speed )
		else:
			player.velocity = Vector2.RIGHT.rotated(self.rotation) * ( player.stats.MAX_SPEED + charge_speed )
	sheild.look_at(player.crosshair_pos)
	animation_player.play(anim_name)
	melee_index = next_index

func charge_invincibility_frames():
	player.hurt_box.set_dodge(true)

func charge_invincibility_frames_out():
	player.hurt_box.set_dodge(false)

func kick_start():
	if can_comboo == false or player.sprite_2d.position.y != -17:
		return
	if !body_group.is_empty():
		body_group.clear()
	if player_ps.melee_rank <= 0:
		melee_damage = player.stats.kick_damage
		melee_anim_play(0.2, 150, "normal_melee", 0)
	else:
		player_ps.melee_rank -= 1
		enhancement_melee = true
		if melee_index == 0:
			melee_damage = player.stats.kick_damage + player.stats.bullet_damage
			melee_anim_play(0.2, 500, "melee_1", 1)
			gpu_particles_2d.restart()
		elif melee_index == 1:
			melee_damage = player.stats.kick_damage + player.stats.bullet_damage * 1.5
			melee_anim_play(0.3, 150, "melee_2", 2)
		elif melee_index == 2:
			melee_damage = player.stats.kick_damage + player.stats.bullet_damage * 2
			melee_anim_play(0.4, 250, "melee_3", 0)
			gpu_particles_2d.restart()
	
	apply_melee_damage_data()

func apply_melee_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"knockback": max(player.stats.bullet_knockback + 100, 1),
		"direction": Vector2.RIGHT.rotated(global_rotation),
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.PLAYER,
		"node": self,
	})
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, round(melee_damage * player.stats.global_damage * player.stats.critical_damage))
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, round(melee_damage * player.stats.global_damage))
		hit_box.damage_data.is_crit = false

func add_damage_data():
	if !body_group.is_empty():
		SoundManager.play_sfx("HurtSounds2")
		ExtensionHooks.notify(ExtensionHooks.on_hit_sfx, ["HurtSounds2", global_position])
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(hit_box.damage_data)
		body_group.clear()

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		
		var hit_direction = (body.position - player.position).normalized()
		
		var luck = randf_range(0, 100)
		if luck < player.stats.critical_luck:
			body.hurt_damage = melee_damage * player.stats.global_damage * player.stats.critical_damage
			body.is_critical_hit = true
			GameEvents.emit_player_melee_critical_hit_enemy(body)
		else:
			body.hurt_damage = melee_damage * player.stats.global_damage
		
		body.hurt_knockback = min( player.stats.bullet_knockback + 200, 1000 )
		body.hurt_direction = hit_direction
		GameEvents.emit_player_melee_hit_enemy(body)
		body.emit_signal("is_hurt")
		SoundManager.play_sfx("HurtSounds2")
		ExtensionHooks.notify(ExtensionHooks.on_hit_sfx, ["HurtSounds2", global_position])
	
	if body.is_in_group("Summoned"):
		
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_knockback = min( player.stats.bullet_knockback + 200, 1000 )
		body.hurt_dir = hit_direction
		
		body.stats.emit_signal("is_hurt")
		SoundManager.play_sfx("HurtSounds2")
		ExtensionHooks.notify(ExtensionHooks.on_hit_sfx, ["HurtSounds2", global_position])
