extends Node2D

signal static_circula_slow_end
signal static_interlace_slow_end
signal static_order_slow_end

@onready var bullet_launcher = $BulletLauncher
@onready var bullet_launcher_2 = $BulletLauncher2
@onready var bullet_timer_1: Timer = $BulletTimer1
@onready var bullet_timer_2: Timer = $BulletTimer2

var can_shoot: bool = true

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

func static_circula_slow():
	if !can_shoot:
		return
	for i in 5:
		bullet_launcher.shoot_bullet()
		await bullet_timer_1.timeout
	static_circula_slow_end.emit()

func static_interlace_slow():
	var first_r = bullet_launcher_2.global_rotation
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
