extends Node2D

signal static_circula_slow_end
signal static_interlace_slow_end
signal static_order_slow_end

@export var stats: EnemyStats

@onready var bullet_launcher = $BulletLauncher
@onready var bullet_launcher_2 = $BulletLauncher2
@onready var bullet_timer_1: Timer = $BulletTimer1
@onready var bullet_timer_2: Timer = $BulletTimer2
@onready var bullet_launcher_base_damage: float = bullet_launcher.bullet_damage
@onready var bullet_launcher_2_base_damage: float = bullet_launcher_2.bullet_damage

var can_shoot: bool = true

var source_faction: int = Faction.ENEMY_SIDE

func _resolve_faction():
	if stats != null and stats.get_parent() != null and stats.get_parent().get("faction") != null:
		source_faction = stats.get_parent().faction
	else:
		source_faction = Faction.ENEMY_SIDE

func _bullet_damage_mult() -> float:
	if stats != null:
		return stats.bullet_damage_mult
	return 1.0

func _ready():
	#static_order_slow_end.connect(test_1)
	#test_1()
	pass

func test_1():
	static_circula_slow()
	await static_circula_slow_end
	static_interlace_slow()
	await static_interlace_slow_end
	static_order_slow()

func stop_shoot():
	can_shoot = false
	if bullet_timer_1 != null:
		bullet_timer_1.stop()
	if bullet_timer_2 != null:
		bullet_timer_2.stop()
	if bullet_launcher_2 != null and bullet_launcher_2.has_method("stop_firing"):
		bullet_launcher_2.stop_firing()

func static_circula_slow():
	if !can_shoot:
		return
	_resolve_faction()
	
	bullet_launcher.source_faction = source_faction
	bullet_launcher.knockback_force = 200
	bullet_launcher.bullet_damage = DamageRouter.scaled_damage(source_faction, _bullet_damage_mult() * bullet_launcher_base_damage, self)
	
	for i in 5:
		bullet_launcher.shoot_bullet()
		await bullet_timer_1.timeout
		if !can_shoot:
			break
	static_circula_slow_end.emit()

func static_interlace_slow():
	var first_r = bullet_launcher_2.global_rotation
	_resolve_faction()
	
	bullet_launcher_2.source_faction = source_faction
	bullet_launcher_2.knockback_force = 200
	bullet_launcher_2.bullet_damage = DamageRouter.scaled_damage(source_faction, _bullet_damage_mult() * bullet_launcher_2_base_damage, self)
	
	bullet_launcher_2.bullet_count = 30
	bullet_launcher_2.bullet_arc = 348
	bullet_timer_2.wait_time = 0.25
	bullet_timer_2.start()
	for i in 20:
		bullet_launcher_2.shoot_bullet()
		SoundManager.play_sfx("GunSounds3")
		await bullet_timer_2.timeout
		bullet_launcher_2.global_rotation += PI/2
		if !can_shoot:
			break
	bullet_launcher_2.global_rotation = first_r
	static_interlace_slow_end.emit()

func static_order_slow():
	var first_r = bullet_launcher_2.global_rotation
	_resolve_faction()
	
	bullet_launcher_2.source_faction = source_faction
	bullet_launcher_2.knockback_force = 200
	bullet_launcher_2.bullet_damage = DamageRouter.scaled_damage(source_faction, _bullet_damage_mult() * bullet_launcher_2_base_damage, self)
	
	bullet_launcher_2.bullet_count = 15
	bullet_timer_2.wait_time = 0.2
	bullet_timer_2.start()
	for i in 25:
		bullet_launcher_2.global_rotation = randf_range(-PI, PI)
		bullet_launcher_2.bullet_arc = randf_range(120, 360)
		bullet_launcher_2.shoot_bullet()
		SoundManager.play_sfx("GunSounds3")
		await bullet_timer_2.timeout
		if !can_shoot:
			break
	bullet_launcher_2.global_rotation = first_r
	static_order_slow_end.emit()

func static_line_fast():
	
	pass


func _on_bullet_timer_1_timeout() -> void:
	SoundManager.play_sfx("LaserSounds1")
	bullet_launcher.shoot_bullet()
