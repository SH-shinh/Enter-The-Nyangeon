extends Node2D

@export var player: Node
@export var player_ps: Node
@onready var timer = $Timer
@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d = $GPUParticles2D

var summoned_group: Dictionary = {}
var sort_group: Array = []

func kick_start():
	if timer.time_left <= 0 and player.sprite_2d.position.y == -17:
		SoundManager.play_sfx("Swing1")
		animation_player.play("melee_anim")
		timer.start()

func can_jump():
	player.can_jump = true

func not_jump():
	player.can_jump = false

func _physics_process(delta):
	if player.graphics.scale.x > 0:
		scale.y = 1
	else:
		scale.y = -1

func sort_summoned():
	if sort_group.size() != 0:
		sort_group.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)


func upgrade_summoned():
	
	if sort_group.size() != 0:
		
		SoundManager.play_sfx("FlyingPan1")
		gpu_particles_2d.emitting = true
		var body = sort_group[0]
		var has_summoned := summoned_group.has(body)
		if !has_summoned:
			summoned_group[body] = {
				"quantity": 1,
				"level": 1,
				"level_count": 0,
				"level_add": 0
			}
			player_ps.show_progress((3 + summoned_group[body]["level_add"]), summoned_group[body]["quantity"], summoned_group[body]["level"])
		else:
			summoned_group[body]["quantity"] += 1
			
			player_ps.show_progress((3 + summoned_group[body]["level_add"]), summoned_group[body]["quantity"], summoned_group[body]["level"])
			
			if summoned_group[body]["quantity"] >= 3 + summoned_group[body]["level_add"]:
				summoned_group[body]["quantity"] = 0
				summoned_group[body]["level"] += 1
				summoned_group[body]["level_count"] += 1
				if summoned_group[body]["level_count"] >= 10:
					summoned_group[body]["level_count"] = 0
					summoned_group[body]["level_add"] += 1
				body.stats.summoned_damage_add += player_ps.up_v
				body.stats.update_body_ability()
			
			

func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		
		var hit_direction = (body.position - player.position).normalized()
		
		var luck = randf_range(0, 100)
		if luck < player.stats.critical_luck:
			body.hurt_damage = player.stats.kick_damage * player.stats.global_damage * player.stats.critical_damage
			body.is_critical_hit = true
			GameEvents.emit_player_melee_critical_hit_enemy(body)
		else:
			body.hurt_damage = player.stats.kick_damage * player.stats.global_damage
		
		body.hurt_knockback = min( player.stats.bullet_knockback + 200, 1000 )
		body.hurt_direction = hit_direction
		GameEvents.emit_player_melee_hit_enemy(body)
		body.emit_signal("is_hurt")
		SoundManager.play_sfx("HurtSounds2")
	
	if body.is_in_group("Summoned"):
		
		sort_group.append(body)
		sort_summoned()
		
		upgrade_summoned()
		
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_knockback = 50
		body.hurt_dir = hit_direction
		
		body.stats.emit_signal("is_hurt")
	


func _on_area_2d_body_exited(body):
	if body.is_in_group("Summoned"):
		sort_group.remove_at(sort_group.find(body))
		sort_summoned()
