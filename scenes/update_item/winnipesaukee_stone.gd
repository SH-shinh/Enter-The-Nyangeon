extends EquipItem

@onready var stone_bullet: PackedScene = preload("res://scenes/bullet/stone_bullet.tscn")
@onready var cd_timer = $CDTimer

var rail_group: Array = []

var color_num: int

var equip_luck: int

var equip_mult: float
var is_critical: bool

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	equip_mult = 0.8
	equip_luck = 10

func _setup():
	GameEvents.enemy_damage_taken.connect(add_stone_bullet)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	equip_mult += 0.8

func bullet_damage_count():
	var damage: int
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		damage = max(1, round((player.stats.max_hp + player.stats.t_hp) * equip_mult * player.stats.global_damage * player.stats.equip_damage * player.stats.critical_damage))
		is_critical = true
	else:
		damage = max(1, round((player.stats.max_hp + player.stats.t_hp) * equip_mult * player.stats.global_damage * player.stats.equip_damage))
		is_critical = false
	return damage

func shoot_bullet(hit_position: Vector2):

	ProjectileSpawner.spawn_core(
		stone_bullet, "stone_bullet", "BulletRoot", self, Faction.PLAYER_SIDE,
		hit_position, 0.0, Vector2.ZERO,
		true, false, true,
		Callable(),
		Callable(self, "_pre_activate_bullet")
	)

func _pre_activate_bullet(node: Node) -> void:
	node.hit_box.damage_data = DamageData.fill(node.hit_box.damage_data, {
		"knockback": player.stats.bullet_knockback,
		"center": node.hit_box.global_position,
		"type": GameTags.EQUIP_DAMAGE,
		"source": GameTags.EQUIP,
		"flags": ["winnipesaukee_stone"],
		"node": node,
	})

	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		node.hit_box.damage_data.is_crit = true
		node.hit_box.damage_data.base_damage = max(1, round((player.stats.max_hp + player.stats.t_hp) * equip_mult * player.stats.global_damage * player.stats.equip_damage * player.stats.critical_damage))
	else:
		node.hit_box.damage_data.is_crit = false
		node.hit_box.damage_data.base_damage = max(1, round((player.stats.max_hp + player.stats.t_hp) * equip_mult * player.stats.global_damage * player.stats.equip_damage))

	var luck_2 = randf_range(0, 100)
	if luck_2 < equip_luck:
		node.yuuka_bullet()
	else:
		node.stone_bullet()

func add_stone_bullet(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if !damage_data.flags.has("winnipesaukee_stone") and cd_timer.time_left <= 0:
		var hit_body: Node = get_node_or_null(body_path)
		if hit_body == null:
			return
		cd_timer.start()
		shoot_bullet.call_deferred(hit_body.global_position)
