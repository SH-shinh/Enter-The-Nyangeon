extends EquipItem

@export var pool_id: String = "hit_flash"

@onready var variable_zoom_scope_icon: PackedScene = preload("res://scenes/update_item/variable_zoom_scope_icon.tscn")
@onready var hit_flash: PackedScene = preload("res://scenes/bullet/hit_flash.tscn")

var penetrate_num: int = 1

func _on_equip():
	penetrate_num = 1
	attach_rail_icon(variable_zoom_scope_icon)

func _setup():
	GameEvents.player_bullet_hit_enemy.connect(bullet_add_penetrate)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	penetrate_num += 1

func bullet_add_penetrate(bullet_body: Node, enemy_body: Node):
	if bullet_body.get("penetrate") != null and enemy_body.stats.hp <= 0:
		ProjectileSpawner.spawn_core(
			hit_flash, pool_id, "BulletRoot", self, Faction.PLAYER_SIDE,
			bullet_body.global_position, bullet_body.rotation, Vector2.ZERO,
			true, false, true
		)
		bullet_body.penetrate += penetrate_num
