extends EquipItem

@onready var blunderbuss_muzzle: PackedScene = preload("res://scenes/update_item/blunderbuss_muzzle_icon.tscn")
@onready var fire_damage: PackedScene = preload("res://script/fire_damage.tscn")
@onready var shoot_fire_1 = $ShootFire1
var group: Array
var player: Node
var fire_num: int = 1
var damage_group: Array[Node]
var index: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	fire_num = 1
	PlayerData.critical_damage_add += 1
	PlayerData.bullet_recoil_mult += 1
	PlayerData.bullet_speed_mult += 0.5

	player.gun.fire_sounds.pitch_scale *= 1.2
	group = get_tree().get_nodes_in_group("Muzzle")
	for i in group:
		if i.muzzle_use == false:
			var sprite_2d = blunderbuss_muzzle.instantiate()
			i.add_child(sprite_2d)
			i.muzzle_use = true

func _setup():
	GameEvents.player_gun_shoot.connect(add_shoot_fire)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	fire_num += 1

func add_shoot_fire(gun: Node):
	shoot_fire_1.global_position = gun.shoot_position.global_position
	shoot_fire_1.rotation = gun.global_rotation
	shoot_fire_1.active_state()

	var ins
	var max_value = damage_group.size()
	if max_value > 5:
		ins = damage_group[index]
		index = wrapi(index + 1, 0, max_value)
		ins.idle_state()
	else:
		ins = fire_damage.instantiate()
		get_tree().get_first_node_in_group("EquipLayer").call_deferred("add_child", ins)
		damage_group.push_back(ins)

	ins.global_position = gun.shoot_position.global_position
	ins.rotation = gun.global_rotation
	ins.fire_damage = 5 * player.stats.dot_damage
	ins.damage_knockback = 100 + player.stats.bullet_knockback
	ins.fire_num = fire_num
	ins.active_state()
