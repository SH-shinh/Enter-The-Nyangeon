extends CharacterBody2D

signal shot_missile(missile: Node)

var dir: Vector2 = Vector2.ZERO
var dir2: Vector2 = Vector2.ZERO
var dir_v: Vector2 = Vector2.ZERO
var is_look_at: Vector2

var speed: int = 350
const speed_time: float = 0.1
var accel: float

var extra_shoot_time: int = 5

var enemy_body: Array =[]

var shoot_cd_timer_mult: float = 1
var shiroko_drone_damage_add: int = 0
var can_shoot: bool = true

var player: Node

@onready var shiroko_drone = $%ShirokoDrone
@onready var shoot_cd_timer = $ShootCDTimer
@onready var shoot_interval_timer = $ShootIntervalTimer
@onready var fire_sounds = $FireSounds
@onready var shoot_position = $ShootPosition

@onready var missile = preload("res://scenes/update_item/shiro_missile.tscn")

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	shot_missile.connect(missile_hurt_damage)
	GameEvents.enemy_damage_taken.connect(extra_shoot)
	GameEvents.screen_changed.connect(outline_changed)

func outline_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func _physics_process(delta):
	dir = player.global_position
	dir2 = (dir - global_position).normalized()
	speed = min(650, global_position.distance_to(dir) * 1.3 * global_position.distance_to(dir) / 100)
	accel = speed / speed_time
	if dir2 != null:
		if global_position.distance_to(dir) > 80:
			dir_v = dir2
		else:
			dir_v.x = dir2.y
			dir_v.y = -dir2.x
	velocity.x = move_toward(velocity.x, dir_v.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir_v.y * speed, accel * delta)
	move_and_slide()
	
	if enemy_body.size() != 0 and is_instance_valid(enemy_body[0]):
		is_look_at = (enemy_body[0].global_position - self.global_position).normalized()
		shiroko_drone.v = is_look_at.angle()
		if can_shoot == true and shoot_cd_timer.time_left <= 0 and shoot_interval_timer.time_left <= 0:
			auto_shot.call_deferred()
	else:
		if player != null:
			is_look_at = (player.crosshair_pos - self.global_position).normalized()
			shiroko_drone.v = is_look_at.angle()
		else:
			is_look_at = dir_v
			shiroko_drone.v = is_look_at.angle()

func emit_shot_missile(missile: Node):
	shot_missile.emit(missile)

# 联机：上报/应用视觉转向（proxy 通过这两个方法同步 %ShirokoDrone 的朝向 v）
func get_network_visual_rotation() -> float:
	return shiroko_drone.v

func apply_network_visual_rotation(rot: float, delta: float) -> void:
	shiroko_drone.v = rot

func missile_hurt_damage(bullet_body: Node):
	bullet_body.damage_data = DamageData.fill(bullet_body.damage_data, {
		"knockback": player.stats.bullet_knockback,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.EQUIP,
		"node": bullet_body,
	})
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		bullet_body.damage_data.is_crit = true
		bullet_body.damage_data.base_damage = max(1, floor((20 + shiroko_drone_damage_add) * player.stats.equip_damage * player.stats.global_damage * PlayerData.bullet_damage_mult *  player.stats.critical_damage))
	else:
		bullet_body.damage_data.is_crit = false
		bullet_body.damage_data.base_damage = max(1, (20 + shiroko_drone_damage_add) * player.stats.equip_damage * player.stats.global_damage * PlayerData.bullet_damage_mult)
	
	bullet_body.explosion_range = 5 * player.stats.explosion_range * 0.6

func auto_shot():
	shoot_cd_timer.wait_time = 3 * shoot_cd_timer_mult
	shoot_cd_timer.start()
	_shoot_missile()
	can_shoot = false

func _shoot_missile():
	shoot_interval_timer.start()
	if player.stats.bullet_count == 1:
		shoot_position.rotation = is_look_at.angle()
		ProjectileSpawner.spawn_core(
			missile, "shiro_missile", "BulletRoot", self, Faction.PLAYER_SIDE,
			shoot_position.global_position, is_look_at.angle(), Vector2.ZERO,
			false, false, true,
			Callable(self, "_configure_missile"),
			Callable(),
			Callable(self, "_post_missile")
		)
		fire_sounds.play()
	
	else:
		var arc_rad = deg_to_rad(player.stats.bullet_arc)
		var increment = arc_rad / (player.stats.bullet_count - 1)
		for i in player.stats.bullet_count:
			ProjectileSpawner.spawn_core(
				missile, "shiro_missile", "BulletRoot", self, Faction.PLAYER_SIDE,
				shoot_position.global_position, is_look_at.angle() + increment * i - arc_rad / 2, Vector2.ZERO,
				false, false, true,
				Callable(self, "_configure_missile"),
				Callable(),
				Callable(self, "_post_missile")
			)
		
		fire_sounds.play()

func _configure_missile(node: Node) -> void:
	node.kill_time = 110

func _post_missile(node: Node) -> void:
	emit_shot_missile(node)
	GameEvents.emit_equip_shot_position(shoot_position.global_position, node)

func sort_enemy():
	if enemy_body.size() != 0:
		for i in range(enemy_body.size() - 1, -1, -1):
			if enemy_body[i] == null or not is_instance_valid(enemy_body[i]):
				enemy_body.remove_at(i)
		enemy_body.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func extra_shoot(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if shoot_interval_timer.time_left > 0 or !damage_data.is_crit:
		return
	extra_shoot_time -= 1
	if extra_shoot_time <= 0:
		shoot_interval_timer.start()
		_shoot_missile.call_deferred()
		extra_shoot_time = 5

func _on_track_box_body_entered(body):
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
	sort_enemy()

func _on_track_box_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
	sort_enemy()


func _on_shoot_cd_timer_timeout():
	can_shoot = true
