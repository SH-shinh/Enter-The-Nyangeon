extends CharacterBody2D
class_name Player

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FLY,
	FALL,
}

@export var player_card: PlayerCard
@export var ps_card: PSCard
@export var stats: Stats
@export var player_color: Color
@export var long_hair: bool = false
@export var mortar: bool = false
@export var hat_position: float = 13
@export var halo_root_position: float = 17

var ACCELERATION: float

const JUMP_SPEED:int = 10

var gravity := ProjectSettings.get("physics/2d/default_gravity") as float
var is_jump_request:bool = false
var look_dir = null
var is_run_request:bool = false
var is_health_request:bool = false
var hurt_dir: Vector2 = Vector2.ZERO
var hurt_knockback: int = 0
var hurt_damage: int = 0
var health_hp: int = 0

var can_move:bool = true
var can_jump:bool = true
var can_control: bool = true
var player_stop:bool = false

var can_knockback: bool = true

var crosshair_pos: Vector2

var on_hit: bool = false

var is_buff_hurt: bool = false

@onready var gun = $%Gun
@onready var kick = $Kick
@onready var smoke = $GPUParticles2D
@onready var halo = $%Halo
@onready var graphics = $%Graphics
@onready var sprite_2d: AnimatedSprite2D = $%AnimatedSprite2D
@onready var jump_timer = $JumpTimer
@onready var fly_timer = $FlyTimer
@onready var jump_cd_timer = $JumpCDTimer
@onready var halo_root = $%HaloRoot
@onready var jump_sounds = $JumpSounds
@onready var run_sounds = $RunSounds
@onready var run_sounds_timer = $RunSoundsTimer
@onready var onhit_shape_2d = $HitBox/HitboxShape
@onready var invincible_frame = $InvincibleFrame
@onready var invincible_frame_anim = $AnimationPlayer
@onready var on_hit_sounds = $OnHitSounds
@onready var coin_sounds = $CoinSounds
@onready var pause_screen = $CanvasLayer/PauseScreen
@onready var jump_cd_bar = $JumpCDBar
@onready var camera_2d = $Camera2D
@onready var kick_anim = $AnimationPlayer2
@onready var collision_shape_2d = $PickBox/CollisionShape2D
@onready var player_buff_manager = $PlayerBuffManager
@onready var game_ui = $GameUI
@onready var hit_box = $HitBox
@onready var hitbox_shape: CollisionShape2D = $HitBox/HitboxShape
@onready var hit_shape: CollisionShape2D = $CollisionShape2D
@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")

signal is_hurt
signal is_health

func _ready():
	gun.now_bullet_ammo = stats.max_ammo
	GameEvents.player_shot_position.connect(bullet_hit_damage)
	GameEvents.refresh_coin_cost.connect(player_coin_cost)
	GameEvents.player_coins_cost.connect(player_coin_cost)
	GameEvents.game_over.connect(game_over_state)
	GameEvents.crosshair_position.connect(get_crosshair_pos)
	if long_hair == true:
		GameEvents.screen_changed.connect(hair_line_changed)
	invincible_frame.timeout.connect(_on_invincible_frame_end)

func _is_on_floor():
	if sprite_2d.position.y == -17:
		return true

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func hair_line_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func game_over_state(player_dead: bool):
	if stats.hp <= 0:
		player_stop = true

func _unhandled_input(event:InputEvent ) -> void:
	
	if player_stop == false:
		if event.is_action_pressed("move_jump") and can_jump == true :
			is_jump_request = true
		
		if event.is_action_pressed("pause") :
			pause_screen.show_pause()
		
		if event.is_action_pressed("fire"):
			gun.is_shoot = true
		
		if event.is_action_released("fire"):
			gun.is_shoot = false
		
		if event.is_action_pressed("kick"):
			kick.kick_start()
		
		if event.is_action_pressed("reload"):
			gun._ammo_reload()

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	
	if jump_cd_timer.time_left > 0:
		update_jump_cd_bar()
	stats.ammo = ceil(gun.now_bullet_ammo)
	
	
	if can_move == true:
		match state:
			State.IDLE:
				_on_invincible_frame_end()
				move(0.0, delta, ACCELERATION, stats.MAX_SPEED)
				
			State.RUNNING:
				_on_invincible_frame_end()
				move(0.0, delta, ACCELERATION, stats.MAX_SPEED)
				
			State.JUMP:
				move(0.0, delta, ACCELERATION * 1.2, stats.MAX_SPEED * 2)
				
			State.FLY:
				move(gravity / 25, delta, ACCELERATION / 2, stats.MAX_SPEED)
				
			State.FALL:
				move(gravity / 5, delta, ACCELERATION / 2, stats.MAX_SPEED)
	
	if is_health_request == true:
		_on_health()
	
	if jump_cd_timer.time_left > 0.1:
		is_jump_request = false
	is_health_request = false
	
	if player_stop == false:
		sprite_2d.look_at(crosshair_pos)
		if mortar == false:
			gun.look_at(crosshair_pos)
		else:
			var r := get_angle_to(crosshair_pos)
			if r <= 0 and r > -PI/2:
				gun.rotation = r * 0.2 - PI * 0.4
			elif r <= -PI/2:
				gun.rotation = -r * 0.2 - PI * 0.6
			elif r > 0 and r <= PI/2:
				gun.rotation = -r * 0.2 - PI * 0.4
			elif r > PI/2:
				gun.rotation = r * 0.2 - PI * 0.6
		kick.look_at(crosshair_pos)
	gun.position.y = sprite_2d.position.y + 9
	halo_root.position.y = sprite_2d.position.y - halo_root_position
	if long_hair == true:
		$GraphicsGun/Hat.position.y = sprite_2d.position.y - hat_position
		$GraphicsGun.scale.x = graphics.scale.x
		$GraphicsHalo.scale.x = graphics.scale.x
	
	
	if sprite_2d.rotation_degrees > 5:
		sprite_2d.rotation_degrees = 5
	elif sprite_2d.rotation_degrees < -10:
		sprite_2d.rotation_degrees = -10
	
	set_player_lookat(crosshair_pos)
	
	if halo.position.distance_to(halo_root.position) > 0:
		halo.position = lerp(halo.position, halo_root.position, 5 * delta)
	
	while is_run_request == true and run_sounds_timer.time_left == 0:
		run_sounds_timer.start()
	
	if is_run_request ==false:
		run_sounds_timer.stop()
	
	if run_sounds_timer.time_left == run_sounds_timer.wait_time:
		run_sounds.pitch_scale = randf_range(0.75, 1)
		run_sounds.play()

func move(gravity: float, delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var movement_vector = get_movement_vector()
	var direction = movement_vector.normalized()
	
	if Game.control_mode != 0:
		direction = movement_vector
	
	if player_stop == true:
		direction = Vector2.ZERO
	velocity.x = move_toward(velocity.x, direction.x * stats.MAX_SPEED, ACCELERATION * delta)
	velocity.y = move_toward(velocity.y, direction.y * stats.MAX_SPEED, ACCELERATION * delta)
	
	if jump_timer.time_left > 0:
		sprite_2d.position.y -= (JUMP_SPEED / (delta + 1.2)) * Engine.time_scale
		
	else:sprite_2d.position.y += gravity * delta * Engine.time_scale
	
	if sprite_2d.position.y > -17:
		sprite_2d.position.y = -17
	
	move_and_slide()
	
	var collision = get_last_slide_collision()
	if collision:
		if velocity.length() > (stats.MAX_SPEED * 2):
			velocity = velocity.bounce(collision.get_normal()) * 0.4

func set_player_lookat(dir):
	if dir != null:
		look_dir = sprite_2d.global_position + (dir * 1000)
		if dir.x > position.x :
			graphics.scale.x = 1
			halo.flip_h = false

		elif dir.x < position.x :
			graphics.scale.x = -1
			halo.flip_h = true

	else:
		look_dir = null

func get_movement_vector():
	if can_control == true:
		var x_movement: float = Input.get_axis("move_left", "move_right")
		var y_movement: float = Input.get_axis("move_up", "move_down")
		
		return Vector2(x_movement, y_movement)
	else:
		return Vector2.ZERO

func get_next_state(state: State) -> State:
	var is_floor := sprite_2d.position.y == -17
	var can_jump :int= is_floor and jump_cd_timer.time_left == 0
	var is_fly :int= fly_timer.time_left > 0
	var is_still := velocity.x == 0 and velocity.y == 0 and is_floor
	var is_fall :int= fly_timer.time_left == 0 and not is_floor
	var is_jump :int= jump_timer.time_left > 0 and can_jump
	
	if is_jump_request == true and can_jump:
		return State.JUMP
	
	match state:
		
		State.IDLE:
			if not is_still:
				return State.RUNNING
			
		
		State.RUNNING:
			if is_still:
				return State.IDLE
			
		
		State.JUMP:
			if jump_timer.time_left == 0:
				return State.FLY
	
		State.FLY:
			if is_fall:
				return State.FALL
				
		State.FALL:
			if is_floor:
				hit_box.monitoring = true
				hit_box.monitorable = true
				return State.IDLE
		
		
	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			z_index = 0
			sprite_2d.play("idle")
			smoke.emitting = false
			is_run_request = false
	
		State.RUNNING:
			sprite_2d.play("run")
			smoke.emitting = true
			is_run_request = true
		
		State.JUMP:
			z_index = 3
			sprite_2d.play("jump")
			jump_timer.start()
			jump_cd_timer.start()
			jump_sounds.play()
			hit_box.monitoring = false
			hit_box.monitorable = false
			smoke.emitting = true
			is_run_request = false
			GameEvents.emit_player_jump(self.global_position)
		
		State.FLY:
			sprite_2d.play("jump")
			fly_timer.start()
			smoke.emitting = false
			is_run_request = false
		
		State.FALL:
			sprite_2d.play("jump")
			smoke.emitting = false
			is_run_request = false
			

func _on_invincible_frame(anim: bool):
	
	hit_box.set_deferred("monitoring", false)
	hit_box.set_deferred("monitorable", false)
	if anim == true:
		invincible_frame_anim.play("Invincible frame")
		if long_hair == false:
			sprite_2d.material.set_shader_parameter("flash_opacity", 1)
			halo.material.set_shader_parameter("flash_opacity", 0.5)
			await  get_tree().create_timer(0.1).timeout
			sprite_2d.material.set_shader_parameter("flash_opacity", 0.3)
			halo.material.set_shader_parameter("flash_opacity", 0.3)
		else:
			$CanvasGroup.material.set_shader_parameter("flash_opacity", 1)
			halo.material.set_shader_parameter("flash_opacity", 0.5)
			await  get_tree().create_timer(0.1).timeout
			$CanvasGroup.material.set_shader_parameter("flash_opacity", 0.3)
			halo.material.set_shader_parameter("flash_opacity", 0.3)


func _on_invincible_frame_end():
	var is_floor := sprite_2d.position.y == -17
	if invincible_frame.time_left <= 0:
		if is_floor:
			hit_box.monitoring = true
			hit_box.monitorable = true
			on_hit = false
		if long_hair == false:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)
			halo.material.set_shader_parameter("flash_opacity", 0)
		else :
			$CanvasGroup.material.set_shader_parameter("flash_opacity", 0)
			halo.material.set_shader_parameter("flash_opacity", 0)

func _on_hurt():
	if hurt_knockback > 0 and can_knockback == true:
		self.velocity = hurt_dir * hurt_knockback
		hurt_knockback = 0
	if hurt_damage != 0:
		GameEvents.emit_player_is_hurt(self)
		if stats.hurt_invalid > 0:
			stats.hurt_invalid -= 1
			stats.hurt_invalid_changed.emit()
			invincible_frame.start()
			SoundManager.play_sfx("EquipSounds2")
			add_text("IMMUNE!")
			_on_invincible_frame(false)
		
		elif stats.t_hp > 0:
			var hurt_hp = max(1, round(hurt_damage * stats.hurt_mult) - stats.hurt_resis)
			stats.t_hp -= hurt_hp
			GameEvents.emit_player_hurt_t_hp(hurt_hp)
			on_hit_sounds.play()
			invincible_frame.start()
			stats.is_hurt.emit()
			if is_buff_hurt == false:
				_on_invincible_frame(true)
		
		else:
			var hurt_hp = max(1, round(hurt_damage * stats.hurt_mult) - stats.hurt_resis)
			stats.hp -= hurt_hp
			GameEvents.emit_player_hurt_hp(hurt_hp)
			on_hit_sounds.play()
			invincible_frame.start()
			stats.is_hurt.emit()
			if is_buff_hurt == false:
				_on_invincible_frame(true)
		hurt_damage = 0
		is_buff_hurt = false

func add_text(text: String):
	
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	floating_text.label.set("theme_override_colors/font_color", Color(0.8, 0.8, 0.8))
	floating_text.label.set("theme_override_font_sizes/font_size", 18)
	floating_text.global_position = global_position + (Vector2.UP * randf_range(15,25)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(text)

func bullet_hit_damage(shot_position: Vector2, bullet_body: Node):
	var luck = randf_range(0, 100)
	if luck < stats.critical_luck:
		bullet_body.is_critical = true
		bullet_body.bullet_damage = max(1, round(stats.bullet_damage * stats.global_damage * stats.critical_damage))
		GameEvents.emit_player_shot_critical(bullet_body)
	else:
		bullet_body.bullet_damage = max(1, round(stats.bullet_damage * stats.global_damage))
		GameEvents.emit_player_shot_not_critical(bullet_body)
	bullet_body.bullet_knockback = stats.bullet_knockback
	bullet_body.scale = Vector2( stats.bullet_scale, stats.bullet_scale )

func update_jump_cd_bar():
	jump_cd_bar.visible = true
	jump_cd_bar.value = ( jump_cd_timer.time_left / jump_cd_timer.wait_time ) * 0.87 + 0.05

func _on_health():
	
	if health_hp > 0:
		var floating_text = PoolManager.get_pool("floating_text")
		if floating_text == null or floating_text.is_idle == 0:
			floating_text = floating_text_scene.instantiate() as Node2D
			get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
		
		stats.hp += max(1, health_hp * stats.heal_mult)
		floating_text.label.set("theme_override_colors/font_color", Color(0.69, 0.929, 0.278))
		floating_text.label.set("theme_override_font_sizes/font_size", 16)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(str(health_hp))
		health_hp = 0

func is_player_stop():
	if player_stop == false:
		player_stop = true
		self.velocity = Vector2.ZERO
		gun.is_shoot = false
	else:
		player_stop = false

func player_coin_cost(coin_cost: int):
	stats.coin -= coin_cost

func _on_hit_box_body_entered(body):
	if player_stop == true:
		return
	
	if on_hit == true:
		return
	else:
		on_hit = true
	
	if body.is_in_group("Enemy"):
		hurt_dir = (self.global_position - body.global_position ).normalized()
		hurt_knockback = body.stats.Enemy_Knockback - stats.knockback_resis
		hurt_damage = body.stats.Enemy_damage
		emit_signal("is_hurt")
	
	if body.is_in_group("EnemyBullet"):
		hurt_dir = (self.global_position - body.global_position ).normalized()
		hurt_knockback = body.knockback - stats.knockback_resis
		hurt_damage = body.bullet_damage
		emit_signal("is_hurt")
		body.now_penetrate -= 1

func _on_jump_cd_timer_timeout():
	jump_cd_bar.visible = false

func _on_is_hurt():
	_on_hurt()

func _on_stats_pick_up_range_changed():
	collision_shape_2d.get_shape().radius = stats.pick_up_range

func _on_is_health():
	_on_health()

func _on_pick_box_area_entered(area):
	if area.is_in_group("PickItem") :
		area.target = self
		area.pick_up = true
