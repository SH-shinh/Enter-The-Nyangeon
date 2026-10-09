extends EquipItem

@onready var scythe = preload("res://scenes/update_item/murky_hand_scythe_icon.tscn")
@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
@onready var shoot_position = $ShootPosition

var equip_damage: int = 25
var scythe_count: int = 1
var scythe_scale: float = 1.0
var back_num: int = 1
var kill_num: int = 0
var update_num: int = 100

var scythe_group: Array[Node]

func _on_equip():
	back_num = scythe_count

func _setup():
	player = get_tree().get_first_node_in_group("Player")
	shoot_scythe()

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	equip_damage += 18
	scythe_scale += 0.1

func shoot_scythe():
	self.global_rotation = player.gun.global_rotation
	if scythe_count == 1:
		var now_scythe

		if scythe_group.is_empty():
			now_scythe = scythe.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_scythe)
			scythe_group.push_back(now_scythe)
			now_scythe.is_go_back.connect(go_back_num)
			now_scythe.kill_enemy.connect(kill_update)
		else:
			now_scythe = scythe_group[0]

		now_scythe.equip_damage =  equip_damage
		now_scythe.global_position = shoot_position.global_position
		now_scythe.global_rotation = global_rotation
		now_scythe.scale = Vector2(scythe_scale ,scythe_scale)

		now_scythe.active_state()
		ExtensionHooks.notify(ExtensionHooks.on_visual_activated, [now_scythe])

	else:
		for i in scythe_count:
			var now_scythe

			if i >= scythe_group.size():
				now_scythe = scythe.instantiate()
				get_tree().get_first_node_in_group("SELayer").add_child(now_scythe)
				scythe_group.push_back(now_scythe)
				now_scythe.is_go_back.connect(go_back_num)
				now_scythe.kill_enemy.connect(kill_update)
			else:
				now_scythe = scythe_group[i]

			now_scythe.equip_damage =  equip_damage
			now_scythe.scale = Vector2(scythe_scale ,scythe_scale)
			now_scythe.global_position = shoot_position.global_position

			var arc_rad = deg_to_rad(360 - floori(360.0 / scythe_count))
			var increment = arc_rad / (scythe_count - 1)
			now_scythe.global_rotation = (
				global_rotation +
				increment * i -
				arc_rad / 2
			) + (PI/scythe_count)

			now_scythe.active_state()
			ExtensionHooks.notify(ExtensionHooks.on_visual_activated, [now_scythe])

func go_back_num():
	back_num -= 1
	if back_num <=0:
		shoot_scythe()
		back_num = scythe_count

func kill_update():
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)

	kill_num += 1
	if kill_num >= update_num:
		scythe_count += 1
		kill_num = 0
		update_num += 100
		floating_text.set_style(Color(0.726, 0.329, 0.701), 24)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start("+ LEVEL UP")
		return
	floating_text.set_style(Color(0.726, 0.329, 0.701), 24)
	floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(str("X", kill_num))
