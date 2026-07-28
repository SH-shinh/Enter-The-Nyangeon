extends Node2D

@export var player: Node
@onready var collision_shape_2d = $Area2D/CollisionShape2D
@onready var timer = $Timer
@onready var timer_2 = $Timer2
@onready var gpu_2d = $GPUParticles2D


func kick_start():
	if timer.time_left <= 0 and player.sprite_2d.position.y == -17:
		if timer_2.time_left <= 0:
			SoundManager.play_sfx("Swing1")
			collision_shape_2d.disabled = false
			player.kick_anim.play("kick_anim")
			#gpu_2d.emitting = true
			timer_2.start()
		timer.start()

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
		
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_knockback = min( player.stats.bullet_knockback + 200, 1000 )
		body.hurt_dir = hit_direction
		
		body.stats.emit_signal("is_hurt")
		SoundManager.play_sfx("HurtSounds2")
	

func _on_timer_2_timeout():
	collision_shape_2d.disabled = true
