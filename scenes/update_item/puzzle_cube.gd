extends EquipItem

@onready var follow_icon = preload("res://scenes/update_item/puzzle_cube_icon.tscn")

var group: Array = []

var overflow_count: int = 0
var overflow_cd: int = 0

var damage_data: DamageData

func _on_equip():
	GameEvents.enemy_over_kill_damage.connect(dead_overflow_damage)
	GameEvents.global_time_count.connect(time_count)
	damage_data = DamageData.new()
	var sprite_2d = follow_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func time_count():
	if overflow_cd > 0:
		overflow_cd -= 1
		if overflow_cd <= 0:
			overflow_count_add()

func overflow_count_add():
	var target: Node = PoolManager.get_random_active_enemy()
	if target != null:
		var true_damage: int = overflow_count
		target.health_component.request_extra_damage(DamageData.true_hit(true_damage, GameTags.EQUIP, self))

func dead_overflow_damage(overkill_damage: int, _taken_damage_data: DamageData, _body_path: NodePath):
	if overflow_cd <= 0:
		overflow_count = clamp(overkill_damage, 1, 9223372036854775807)
		overflow_cd = 1
