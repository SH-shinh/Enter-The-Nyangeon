extends EquipItem

@onready var ink_cartridge_icon: PackedScene = preload("res://scenes/update_item/ink_cartridge_icon.tscn")
@onready var small_explosion: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var floor_paint: PackedScene = preload("res://script/floor_paint.tscn")

@onready var explosion_interval_timer = $ExplosionIntervalTimer

var color_num: int

var equip_luck: int = 0
var equip_damage: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	attach_rail_icon(ink_cartridge_icon)

func _setup():
	GameEvents.enemy_damage_taken.connect(add_explosion)

func _apply_effect(_quantity: int):
	equip_damage += 20
	equip_luck += 5

func explosion(body: Node):
	ProjectileSpawner.spawn_core(
		small_explosion, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		body.global_position, 0.0, Vector2.ZERO,
		true, false, true,
		Callable(self, "_configure_explosion"),
		Callable(self, "_pre_activate_explosion"),
		Callable(self, "_post_explosion")
	)
	
	if PoolManager.fx_allowed(&"floor_paint"):
		var ins_2 = PoolManager.get_pool("floor_paint")
		if ins_2 == null or ins_2.is_idle == 0:
			ins_2 = floor_paint.instantiate()
			get_tree().get_first_node_in_group("FloorLayer").add_child(ins_2)
		
		ins_2.global_position = body.global_position
		ins_2.active_state()

func _configure_explosion(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"knockback": player.stats.bullet_knockback,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.EQUIP,
	})
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		node.damage_data.base_damage = max(1, ((equip_damage + player.stats.bullet_damage * 0.4) * player.stats.global_damage * player.stats.critical_damage * player.stats.equip_damage))
		node.damage_data.is_crit = true
	else:
		node.damage_data.base_damage = max(1, ((equip_damage + player.stats.bullet_damage * 0.4) * player.stats.global_damage * player.stats.equip_damage))
		node.damage_data.is_crit = false
	
	node.explosion_range = 3 * player.stats.explosion_range

func _pre_activate_explosion(node: Node) -> void:
	node.damage_data.hit_box_center = node.global_position

func _post_explosion(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	node.is_small_explosion()

func add_explosion(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if explosion_interval_timer.time_left > 0:
		return
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		if randf_range(0,400) < equip_luck + player.stats.luck:
			explosion_interval_timer.start()
			var body: Node = get_node_or_null(body_path)
			if body == null:
				return
			explosion.call_deferred(body)
