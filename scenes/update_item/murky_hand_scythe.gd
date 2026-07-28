extends Node2D

@onready var scythe = preload("res://scenes/update_item/murky_hand_scythe_icon.tscn")
@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
@onready var shoot_position = $ShootPosition

var equip_damage: int = 25
var scythe_count: int = 1
var scythe_scale: float = 1.0
var back_num: int
var num: int
var kill_num: int = 0
var update_num: int = 100

func _ready():
	back_num = scythe_count
	shoot_scythe()
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "murky_hand_scythe":
		return
	if current_upgrade["murky_hand_scythe"]["quantity"] == 1:
		return
	num = current_upgrade["murky_hand_scythe"]["quantity"]
	equip_damage += 18
	scythe_scale += 0.1
	PlayerData.update_player_ability()

func shoot_scythe():
	self.global_rotation = (self.global_position - get_global_mouse_position()).angle()
	if scythe_count == 1:
		var now_scythe = scythe.instantiate()
		now_scythe.equip_damage =  equip_damage
		
		now_scythe.position = shoot_position.global_position
		now_scythe.global_rotation = global_rotation + PI
		now_scythe.scale *= scythe_scale
		#shoot_position.rotation = global_rotation
		get_tree().get_first_node_in_group("SELayer").add_child(now_scythe)
		now_scythe.is_go_back.connect(go_back_num)
		now_scythe.kill_enemy.connect(kill_update)
		
	
	else:
		for i in scythe_count:
			var now_scythe = scythe.instantiate()
			now_scythe.equip_damage =  equip_damage
			now_scythe.scale *= scythe_scale
			now_scythe.position = shoot_position.global_position
			
			var arc_rad = deg_to_rad(360 - (360 / scythe_count))
			var increment = arc_rad / (scythe_count - 1)
			now_scythe.global_rotation = (
				global_rotation +
				increment * i -
				arc_rad / 2
			) + (PI/scythe_count)
			get_tree().get_first_node_in_group("SELayer").add_child(now_scythe)
			now_scythe.is_go_back.connect(go_back_num)
			now_scythe.kill_enemy.connect(kill_update)

func go_back_num():
	back_num -= 1
	if back_num <=0:
		shoot_scythe()
		back_num = scythe_count

func kill_update():
	var floating_text
	if FloatingPool.floating_pool.size() > 100:
		
		floating_text = FloatingPool.floating_pool[0]
		floating_text.reset()
		FloatingPool.call_pool()
	else:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	kill_num += 1
	if kill_num >= update_num:
		scythe_count += 1
		kill_num = 0
		update_num += 100
		floating_text.label.set("theme_override_colors/font_color", Color(0.726, 0.329, 0.701))
		floating_text.label.set("theme_override_font_sizes/font_size", 24)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start("+ LEVEL UP")
		return
	floating_text.label.set("theme_override_colors/font_color", Color(0.726, 0.329, 0.701))
	floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(str("X", kill_num))
