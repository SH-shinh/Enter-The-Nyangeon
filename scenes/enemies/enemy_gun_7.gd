extends EnemyGun

@export var type: Array[String]

var index: int = randi_range(0, 2)

func shoot_bullet():
	SoundManager.play_sfx("GunSounds5")
	fire_anim.play("RESET")
	fire_anim.play("fire_anim")
	
	bullet_launcher.bullet_damage = stats.bullet_damage_mult * bullet_launcher.bullet_damage
	bullet_launcher.knockback_force = knockback_force
	_apply_converted_source()
	bullet_launcher.shoot_bullet.call_deferred()
	
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = bullet_launcher.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()


func gun_shot():
	if bullet_launcher.is_active == true:
		shoot_end.emit()
		return
	index = wrapi( index + 1, 0, 3)
	bullet_launcher.formation_type = type[index]
	shoot_bullet()
	shoot_end.emit()
