extends EquipItem

@export var enemy_buff: Buff

var player: Node
var base_explosion_range: float = 3.0
var explosion_damage: int = 1
@onready var explosion_ins: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var matcha_ramune_hat_icon = preload("res://scenes/update_item/matcha_ramune_icon.tscn")

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.enemy_damage_taken.connect(damage_count)
	attach_hat_icon(matcha_ramune_hat_icon)

func damage_count(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.POISON_DAMAGE):
		var enemy_body = get_node_or_null(body_path)
		if enemy_body == null:
			return
		if enemy_body.enemy_buff_manager.current_buff.has("fire_dot") and enemy_body.enemy_buff_manager.current_buff.has("poison_dot"):
			explosion_damage = enemy_body.enemy_buff_manager.current_buff["poison_dot"]["value"] * 1.2
			add_dot_explosion(enemy_body.global_position)

func add_dot_explosion(explosion_position: Vector2):

	ProjectileSpawner.spawn_core(
		explosion_ins, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		explosion_position, 0.0, Vector2.ZERO,
		true, false, true,
		Callable(),
		Callable(self, "_pre_activate_explosion"),
		Callable(self, "_post_explosion")
	)

func _pre_activate_explosion(node: Node) -> void:
	node.explosion_range = max(1, player.stats.explosion_range * 0.5) * base_explosion_range

	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": explosion_damage * player.stats.dot_damage,
		"crit": false,
		"knockback": player.stats.bullet_knockback,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.EQUIP,
		"center": node.global_position,
	})

func _post_explosion(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	node.is_small_explosion()
