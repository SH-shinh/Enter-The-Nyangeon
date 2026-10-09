extends EquipItem

@onready var mint_chocolate_parfait_icon = preload("res://scenes/update_item/mint_chocolate_parfait_icon.tscn")

var group: Array = []

func _on_equip():
	var sprite_2d = mint_chocolate_parfait_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func _setup():
	# 改为命中瞬间信号（携带 live bullet；联机下 en_damage_taken 是权威延迟回传，那时子弹已回池）
	GameEvents.player_projectile_hit.connect(_on_projectile_hit)

func _on_projectile_hit(bullet_body: Node, hit_body: Node):
	if bullet_body == null or not is_instance_valid(bullet_body):
		return
	var damage_data = bullet_body.get("damage_data")
	if damage_data == null or not damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		return
	if bullet_body.get("flight_time") == null:
		return
	var enemy_body: Node = hit_body
	while enemy_body != null and enemy_body.get("health_component") == null:
		enemy_body = enemy_body.get_parent()
	if enemy_body == null or enemy_body.get("health_component") == null:
		return
	enemy_body.health_component.damage_multiplier += (bullet_body.flight_time * 0.2)
