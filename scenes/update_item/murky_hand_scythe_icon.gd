extends HitBox

signal is_go_back
signal kill_enemy

@onready var fly_timer = $FlyTimer
@onready var surround_timer = $SurroundTimer
@onready var sprite_2d = $Sprite2D
@onready var collision_shape_2d = $CollisionShape2D


var equip_damage: int
var equip_knockback: int

var accel: float
var speed: int = 400
var speed_time: float = 0.1

var first_point: Vector2

var dir: Vector2
var dir_v: Vector2

var player: Node

var velocity: Vector2
var body_group: Array[Node]

var is_idle: int = 1

# 联机远端驱动：位置/朝向/缩放在 _physics_process 里向网络目标插值；
# 由 mod 调用 network_apply_visual_state 置位后，跳过本地「归位到 player」逻辑。
@export var net_pos_lerp_speed: float = 18.0
var _net_remote_driven: bool = false
var _net_target_pos: Vector2 = Vector2.ZERO
var _net_target_rot: float = 0.0
var _net_target_scale: Vector2 = Vector2.ONE

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.global_time_count.connect(time_count)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func idle_state():
	is_idle = 1
	self.visible = false
	global_position = Vector2.ZERO
	collision_shape_2d.set_deferred("disabled", true)

func active_state():
	is_idle = 0
	# 每次激活清远端驱动标记：远端克隆待状态到达后吸附到拥有者轨迹。
	_net_remote_driven = false
	self.visible = true
	collision_shape_2d.set_deferred("disabled", false)
	dir = Vector2.RIGHT.rotated(global_rotation)
	velocity = dir * speed
	fly_timer.start()
	first_point = self.global_position
	apply_melee_damage_data()

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	if _net_remote_driven:
		var w := 1.0 - exp(-net_pos_lerp_speed * delta)
		global_position = global_position.lerp(_net_target_pos, w)
		global_rotation = lerp_angle(global_rotation, _net_target_rot, w)
		scale = scale.lerp(_net_target_scale, w)
		sprite_2d.rotation += delta * 15
		return
	
	if fly_timer.time_left > 0:
		dir_v = dir
	elif surround_timer.time_left > 0:
		dir = (self.global_position - first_point).normalized()
		dir_v.x = -dir.y
		dir_v.y = dir.x
	else:
		dir_v = (player.global_position - self.global_position).normalized()
		if global_position.distance_to(player.global_position) < 15:
			idle_state()
			is_go_back.emit()
	accel = speed / speed_time
	velocity.x = move_toward(velocity.x, dir_v.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir_v.y * speed, accel * delta)
	
	global_position += velocity * delta
	sprite_2d.rotation += delta * 15

func time_count():
	if is_idle == 1:
		return
	
	add_damage_data()

func apply_melee_damage_data():
	damage_data = DamageData.fill(damage_data, {
		"knockback": max(player.stats.bullet_knockback + 50, 1),
		"direction": Vector2.RIGHT.rotated(global_rotation),
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.EQUIP,
		"node": self,
	})
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		damage_data.base_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
		damage_data.is_crit = true
	else:
		damage_data.base_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage)
		damage_data.is_crit = false
	
	damage_data.on_damage_dealt.append(func(victim: Node, _actual_damage: float):
		if victim == null or not is_instance_valid(victim):
			return
		var victim_stats = victim.get("stats")
		if victim_stats == null:
			return
		if victim_stats.hp <= 0:
			kill_enemy.emit()
		)

# 联机：导出持续视觉状态（世界坐标 + 本体朝向 + 缩放）。
func network_get_visual_state() -> Dictionary:
	return {"p": global_position, "r": global_rotation, "sc": scale}


# 联机：套用远端状态；位置/朝向/缩放在 _physics_process 平滑插值，并跳过本地归位逻辑。
func network_apply_visual_state(p: Vector2, rot: float, sc: Vector2) -> void:
	if not p.is_finite():
		return
	_net_target_pos = p
	_net_target_rot = rot if is_finite(rot) else global_rotation
	_net_target_scale = sc if sc.is_finite() else scale
	if not _net_remote_driven:
		_net_remote_driven = true
		global_position = _net_target_pos
		global_rotation = _net_target_rot
		scale = _net_target_scale


func add_damage_data():
	if !body_group.is_empty():
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(damage_data)

func _on_fly_timer_timeout():
	surround_timer.start()

func _on_area_2d_body_entered(body):
	
	if body.is_in_group("Enemy"):
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage)
		body.hurt_knockback = player.stats.bullet_knockback * 1.5
		body.hurt_direction = hit_direction
		if randf_range(0,100) < player.stats.critical_luck:
			body.hurt_damage *= player.stats.critical_damage
			body.is_critical_hit = true
		body.emit_signal("is_hurt")
		GameEvents.emit_equip_hit_enemy(body, self)
		if body.stats.hp <=0:
			GameEvents.emit_equip_kill_enemy()
			kill_enemy.emit()

func _on_area_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_area_exited(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and body_group.has(hurtbox):
		body_group.remove_at(body_group.find(hurtbox))
