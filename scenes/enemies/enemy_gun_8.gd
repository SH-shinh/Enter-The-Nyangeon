extends EnemyGun

@export var enemy_body: Node

@onready var timer_2: Timer = $Timer2

func shoot_bullet():
	SoundManager.play_sfx("GunSounds6")
	fire_anim.play("RESET")
	fire_anim.play("fire_anim")
	
	bullet_launcher.bullet_damage = stats.bullet_damage_mult * bullet_launcher.bullet_damage
	bullet_launcher.knockback_force = knockback_force
	_apply_converted_source()
	bullet_launcher.shoot_bullet()
	
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = bullet_launcher.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()


func gun_shot():
	begin_burst()
	bullet_launcher.red_line_v(true)
	timer.start()

func _stop_extra() -> void:
	if timer_2 != null:
		timer_2.stop()

func _on_timer_timeout() -> void:
	if firing_stopped:
		return
	enemy_body.sniper = false
	timer_2.start()

func _on_timer_2_timeout() -> void:
	if firing_stopped:
		return
	shoot_bullet()
	bullet_launcher.red_line_v(false)
	await bullet_launcher.animation_player.animation_finished
	enemy_body.sniper = true
	shoot_end.emit()
