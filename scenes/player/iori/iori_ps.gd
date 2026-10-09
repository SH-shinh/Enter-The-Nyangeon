extends PlayerPS

signal iiiasd

@export var bullet_count: int = 3
@export var pool_id: String = "hit_flash_2"

@onready var hit_flash: PackedScene = preload("res://scenes/bullet/hit_flash_2.tscn")

var bullet_group: Array[Node]
var _ious_parent_bullet: Node = null
var damage_mult: float = 0.5
var collision_damage_mult: float = 1.2

func _ready() -> void:
	super._ready()
	# 改为监听"命中瞬间、携带 live bullet"的信号（联机下 en_damage_taken 走权威延迟回传，
	# 那时 source_node 指向的子弹已回池，分裂失效）
	GameEvents.player_projectile_hit.connect(_on_projectile_hit)

func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	
	if now_t == 1:
		damage_mult = 0.6
		PlayerData.collision_num_add += 2
		PlayerData.update_player_ability()
	elif now_t == 2:
		damage_mult = 0.8
		PlayerData.collision_num_add += 2
		PlayerData.update_player_ability()
		GameEvents.player_bullet_collision.connect(update_bullet_damage)
	elif now_t == 3:
		damage_mult = 1.0
		collision_damage_mult = 1.5

func _on_projectile_hit(bullet_body: Node, _hit_body: Node):
	if bullet_body == null or not is_instance_valid(bullet_body):
		return
	var damage_data = bullet_body.get("damage_data")
	if damage_data == null:
		return
	if not damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		return
	if not damage_data.source_type.has(GameTags.PLAYER):
		return
	# 分裂产物不再触发分裂：只有原始子弹（玩家枪械 / 道具发射器）可分裂
	if damage_data.flags.has(GameTags.SPLIT_CHILD):
		return
	if not bullet_body.has_method("apply_penetrate_dealt"):
		return
	if bullet_body.get("is_idle") == 1:
		return
	if bullet_body.penetrate <= 1:
		shoot_bullet(bullet_body as Node2D)

func add_flash(bullet_body: Node2D):
	ProjectileSpawner.spawn_core(
		hit_flash, pool_id, "BulletRoot", self, Faction.PLAYER_SIDE,
		bullet_body.global_position, bullet_body.rotation, Vector2.ZERO,
		true, false, true
	)

func remove_bullet(bullet_body: Node):
	if bullet_group.has(bullet_body):
		if bullet_body.in_idle.is_connected(remove_bullet):
			bullet_body.in_idle.disconnect(remove_bullet)
		bullet_group.remove_at(bullet_group.find(bullet_body))

# 复制父级 damage_data 后，剔除绑定在父子弹上的 on_damage_dealt 回调；
# 保留玩家/道具挂载的通用命中回调（其绑定对象不是该子弹）。
func _keep_foreign_callbacks(data: DamageData, parent_bullet: Node) -> void:
	if data == null:
		return
	var kept: Array[Callable] = []
	for cb in data.on_damage_dealt:
		if cb.get_object() != parent_bullet:
			kept.append(cb)
	data.on_damage_dealt = kept

func shoot_bullet(bullet_body: Node2D):
	if !bullet_group.has(bullet_body):
		SoundManager.play_sfx("HurtSounds2")
		ExtensionHooks.notify(ExtensionHooks.on_hit_sfx, ["HurtSounds2", bullet_body.global_position])
		add_flash(bullet_body)
		_ious_parent_bullet = bullet_body
		var arc_rad = deg_to_rad(30)
		var increment = arc_rad / (bullet_count - 1)
		for i in bullet_count:
			ProjectileSpawner.spawn_core(
				gun.bullet, bullet_body.pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
				bullet_body.global_position, bullet_body.global_rotation + increment * i - arc_rad / 2, bullet_body.scale,
				false, false, true,
				Callable(self, "_configure_split_bullet"),
				Callable(),
				Callable(self, "_post_split_bullet")
			)
		_ious_parent_bullet = null

func _configure_split_bullet(node: Node) -> void:
	node.speed = _ious_parent_bullet.speed
	node.penetrate = stats.bullet_penetrate
	node.collision_num = _ious_parent_bullet.collision_num
	node.kill_time = player.stats.bullet_kill_time * 10
	node.damage_data = _ious_parent_bullet.damage_data.duplicate(true)
	node.damage_data.base_damage = max(1, round(node.damage_data.base_damage * damage_mult))
	_keep_foreign_callbacks(node.damage_data, _ious_parent_bullet)
	node.damage_data.flags.append(GameTags.SPLIT_CHILD)
	if node.has_method("apply_penetrate_dealt"):
		node.apply_penetrate_dealt()

func _post_split_bullet(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	bullet_group.append(node)
	if !node.in_idle.is_connected(remove_bullet):
		node.in_idle.connect(remove_bullet)

func update_bullet_damage(bullet_body: Node):
	bullet_body.damage_data.base_damage *= collision_damage_mult
