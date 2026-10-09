class_name HurtBox
extends Area2D

@export var body: Node
@export var is_player: bool = false
@export var contact_interval: float = 0.2       #同一敌人的接触伤害冷却
@export var contact_check_interval: float = 0.1 #接触探针轮询间隔

signal hit_received(damage_data: HealthChangeData)

var contact_invincible: bool = false

var _contact_probe: Area2D = null
var _contacts: Dictionary = {}   #非玩家：接触中的敌人 body
var _contact_cd: Dictionary = {}
var _check_accum: float = 0.0

func _ready():
	area_entered.connect(_on_area_entered)
	collision_mask |= 8
	if is_player:
		_build_contact_probe()
	else:
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

# 普通无敌帧：挡"目标侧检测"（普通子弹/近战 area_entered = monitoring）
# 与"接触免疫"（contact_invincible）；但 monitorable 不动 ——
# "来源侧检测"（如 erosion_tower 激光的 get_overlapping_areas）仍可无视无敌帧命中。
func set_invulnerable(v: bool):
	monitoring = not v
	contact_invincible = v

# 闪避无敌帧（跳跃/蓄力等）：额外关 monitorable，连"来源侧检测"的激光也一起挡。
func set_dodge(v: bool):
	set_invulnerable(v)
	monitorable = not v

func _on_area_entered(hitbox: Area2D):
	if hitbox is HitBox:
		# 自管理命中的子弹自行检测/结算（形状常开的按目标冷却），避免双结算。
		if hitbox.manages_own_hits:
			return
		if hitbox.damage_data == null:
			return
		hitbox.damage_data.hit_box_center = hitbox.global_position
		hit_received.emit(hitbox.damage_data)

func _on_body_entered(entered_body: Node):
	if not entered_body.is_in_group("Enemy"):
		return
	_contacts[entered_body] = true
	_contact_cd[entered_body] = 0.0
	_emit_contact(entered_body)

func _on_body_exited(entered_body: Node):
	_contacts.erase(entered_body)
	_contact_cd.erase(entered_body)

# 常驻接触探针：复制本节点的碰撞形状，只检测敌人 body，不随无敌帧开关。
# 这样"一直贴着没离开"的敌人不会因 monitoring 重开检测不到，无敌帧结束后能立刻重新结算。
func _build_contact_probe():
	_contact_probe = Area2D.new()
	_contact_probe.collision_layer = 0
	_contact_probe.collision_mask = 8
	_contact_probe.monitoring = true
	_contact_probe.monitorable = false
	add_child(_contact_probe)
	for child in get_children():
		if child is CollisionShape2D:
			var dup := CollisionShape2D.new()
			dup.shape = child.shape
			dup.transform = child.transform
			dup.disabled = child.disabled
			_contact_probe.add_child(dup)

func _physics_process(delta: float):
	if _contact_probe == null and _contacts.is_empty():
		return
	_check_accum += delta
	if _check_accum < contact_check_interval:
		return
	_check_accum = 0.0
	if _contact_probe != null:
		_poll_probe()
	else:
		_poll_contacts()

# 玩家：探针重叠轮询（monitoring 会被无敌帧开关，探针不受影响）
func _poll_probe():
	var seen: Dictionary = {}
	for entered_body in _contact_probe.get_overlapping_bodies():
		if not entered_body.is_in_group("Enemy"):
			continue
		seen[entered_body] = true
		if contact_invincible:
			_contact_cd[entered_body] = contact_interval
			continue
		if not _contact_cd.has(entered_body):
			_contact_cd[entered_body] = contact_interval #新接触立即结算
		else:
			_contact_cd[entered_body] += contact_check_interval
		if _contact_cd[entered_body] >= contact_interval:
			_contact_cd[entered_body] = 0.0
			_emit_contact(entered_body)
	for tracked in _contact_cd.keys():
		if not seen.has(tracked):
			_contact_cd.erase(tracked)

# 敌人/召唤物：body_entered/body_exited 维护接触列表后按冷却重判
func _poll_contacts():
	for entered_body in _contacts.keys():
		if not is_instance_valid(entered_body):
			_contacts.erase(entered_body)
			_contact_cd.erase(entered_body)
			continue
		if contact_invincible:
			_contact_cd[entered_body] = contact_interval
			continue
		_contact_cd[entered_body] = _contact_cd.get(entered_body, 0.0) + contact_check_interval
		if _contact_cd[entered_body] >= contact_interval:
			_contact_cd[entered_body] = 0.0
			_emit_contact(entered_body)

func _emit_contact(entered_body: Node):
	if not is_instance_valid(entered_body):
		return
	if entered_body.get("damage_data") == null:
		return
	var my_team: int = Faction.ENEMY_SIDE
	if owner != null:
		my_team = Faction.of_entity(owner)
	if not Faction.hostile_to(entered_body.damage_data.source_type, my_team):
		return
	entered_body.damage_data.hit_box_center = entered_body.global_position
	hit_received.emit(entered_body.damage_data)
