class_name PlayerMortarBullet
extends PlayerBullet

@export var fall_value: float = 980
@export var life_time: int = 4
@export var base_explosion_range: float = 1

@onready var fall_timer = $FallTimer
@onready var explosion_damage: PackedScene = preload("res://script/explosion_damage.tscn")

var mouse_length: float
var fly_time: float
var fly_num: float
var target: Vector2
var homing_landing: bool = false

func _ready():
	super._ready()
	fall_timer.timeout.connect(bullet_explosion)

# 榴弹不产生直击伤害：关闭自检 HurtBox，只靠落点爆炸（bullet_explosion）。
func does_direct_hit() -> bool:
	return false

func idle_state():
	super.idle_state()
	homing_landing = false
	fall_timer.stop()

func active_state():
	if is_ready == false:
		return
	super.active_state()
	count_fly_time()

func apply_penetrate_dealt():
	pass

func count_fly_time():
	if homing_landing:
		var target_enemy: Node = Targeting.nearest_enemy(global_position)
		if target_enemy != null:
			direction = (target_enemy.global_position - global_position).normalized()
			mouse_length = global_position.distance_to(target_enemy.global_position)
	
	if mouse_length == 0:
		if target_position != Vector2.ZERO:
			mouse_length = self.global_position.distance_to(target_position)
		else:
			mouse_length = randi_range(50,150)
	
	fly_time = mouse_length / speed
	
	if kill_time <= 0:
		kill_time = 1
	
	if fly_time > (float(kill_time) / 10):
		mouse_length = (float(kill_time) / 10) * speed
		fly_time = mouse_length / speed
	if fly_time != 0:
		fall_timer.wait_time = fly_time
	fall_timer.start()
	fly_num = PI / fly_time
	target = direction * mouse_length
	velocity.x = target.x / fly_time
	velocity.y = target.y / fly_time
	velocity.y -= fall_value * fly_time / 2

func fly_move(delta: float):
	velocity.y += fall_value * delta

func _physics_process(delta):
	if is_idle == 1:
		return
	
	if slow_down == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	if can_r == true:
		r_move(delta)
	else:
		fly_move(delta)
	
	global_position += velocity * delta
	flight_time += delta
	rotation = velocity.normalized().angle()

func bullet_explosion():
	if damage_data == null or player == null or not is_instance_valid(player):
		idle_state()
		return
	
	ProjectileSpawner.spawn_core(
		explosion_damage, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		self.global_position, 0.0, Vector2.ZERO,
		false, false, true,
		Callable(self, "_configure_explosion"),
		Callable(),
		Callable(self, "_post_explosion")
	)
	
	GameEvents.emit_player_bullet_explosion(self.global_position)
	
	if collision_num > 0:
		collision_num -= 1
		mouse_length /= 1.2
		speed /= 1.2
		direction = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized()
		count_fly_time()
		GameEvents.emit_player_bullet_collision(self)
	else:
		GameEvents.emit_player_bullet_free_position(self.global_position)
		idle_state()

func _configure_explosion(node: Node) -> void:
	node.explosion_range = max(1, player.stats.explosion_range * 0.8) * max(1, player.stats.bullet_scale * 0.6) * base_explosion_range
	node.damage_data = damage_data.duplicate(true)
	if not node.damage_data.damage_type.has(GameTags.EXPLOSION_DAMAGE):
		node.damage_data.damage_type.append(GameTags.EXPLOSION_DAMAGE)
	node.damage_data.hit_box_center = self.global_position

func _post_explosion(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	node.flight_time = flight_time
	node.is_small_explosion()

func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		bullet_explosion()
