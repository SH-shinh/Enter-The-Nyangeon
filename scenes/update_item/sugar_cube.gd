extends EquipItem

const FIRE_ID := "fire_dot"
const CHILL_ID := "chill_dot"
const MAX_HP_RATIO := 0.1
const STEAM: PackedScene = preload("res://scenes/update_item/sugar_cube_steam.tscn")

func _setup() -> void:
	GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)

func _on_enemy_damage_taken(_final_damage: int, damage_data: DamageData, body_path: NodePath) -> void:
	if damage_data == null or not damage_data.damage_type.has(GameTags.CHILL_DAMAGE):
		return
	var enemy: Node = get_node_or_null(body_path)
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null or not manager.current_buff.has(FIRE_ID):
		return
	var fire_entry: Dictionary = manager.current_buff[FIRE_ID]
	if fire_entry["max_layer"] <= 0 or fire_entry["layer"] < fire_entry["max_layer"]:
		return
	var stats = enemy.get("stats")
	var health = enemy.get("health_component")
	if stats == null or health == null:
		return
	var true_damage: int = max(1, int(round(stats.max_hp * MAX_HP_RATIO)))
	health.request_extra_damage(DamageData.true_hit(true_damage, GameTags.EQUIP, self))
	for id in [FIRE_ID, CHILL_ID]:
		if manager.current_buff.has(id):
			manager.remove_buff(manager.current_buff[id]["resource"])
	PoolManager.spawn_fx("sugar_cube_steam", STEAM, enemy)
