extends EnemyGun

func _ready():
	super._ready()
	stats.is_dead.connect(gun_shot)

func shoot_bullet():
	
	bullet_launcher.bullet_damage = stats.bullet_damage_mult * bullet_launcher.bullet_damage
	bullet_launcher.knockback_force = knockback_force
	_apply_converted_source()
	bullet_launcher.shoot_bullet.call_deferred()

func gun_shot():
	shoot_bullet()
