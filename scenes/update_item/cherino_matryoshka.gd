extends EquipItem

@onready var range_explosion: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var cherino_matryoshka_icon = preload("res://scenes/update_item/cherino_matryoshka_icon.tscn")
@onready var range_explosion_anim = $RangeExplosion

var player: Node
var explosion_num: int = 0
var group: Array = []

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	var sprite_2d = cherino_matryoshka_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func _setup():
	GameEvents.explosion_damage.connect(explosion_count)

func explosion_count(_explosion_position: Vector2, _explosion_range: float):
	explosion_num += 1
	if explosion_num > 10:
		explosion_num = 0
		add_range_explosion()

func add_range_explosion():
	ProjectileSpawner.spawn_core(
		range_explosion, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		self.global_position, 0.0, Vector2.ZERO,
		true, false, true,
		Callable(),
		Callable(self, "_pre_activate_explosion")
	)

	range_explosion_anim.scale = Vector2(5 * player.stats.explosion_range, 5 * player.stats.explosion_range)
	range_explosion_anim.play_anim()

func _pre_activate_explosion(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"knockback": player.stats.bullet_knockback,
		"center": node.global_position,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.EQUIP,
		"node": node,
	})

	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		node.damage_data.is_crit = true
		node.damage_data.base_damage = (10 + player.stats.bullet_damage) * player.stats.global_damage * player.stats.critical_damage * player.stats.equip_damage
	else:
		node.damage_data.is_crit = false
		node.damage_data.base_damage = (10 + player.stats.bullet_damage) * player.stats.global_damage * player.stats.equip_damage

	node.explosion_range = 5 * player.stats.explosion_range
