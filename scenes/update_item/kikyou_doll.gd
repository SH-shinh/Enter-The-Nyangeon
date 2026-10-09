extends EquipItem

var poison_damage: int
var damage_mult: float = 0.4
var group: Array = []
var doll: Node

var ring: Node

var poison_cd: int = 40
var now_cd: int = 40

@onready var kikyou_doll_icon = preload("res://scenes/update_item/kikyou_doll_icon.tscn")
@onready var poison_ring: PackedScene = preload("res://scenes/bullet/poison_ring.tscn")

func time_count():
	if now_cd > 0:
		now_cd -= 1
		if now_cd <= 0:
			add_poison_ring()
			now_cd = poison_cd

func add_poison_ring():
	update_poison_damage()
	if ring != null:
		if doll != null:
			ring.hit_box.damage_data = DamageData.fill(ring.hit_box.damage_data, {
				"damage": poison_damage,
				"type": GameTags.POISON_DAMAGE,
				"source": GameTags.EQUIP,
				"knockback": 0,
				"node": ring,
			})
			ring.global_position = doll.global_position
			ring.active_state()
			ExtensionHooks.notify(ExtensionHooks.on_visual_activated, [ring])
	else:
		var ins = poison_ring.instantiate()
		get_tree().get_first_node_in_group("SELayer").add_child(ins)

		ins.hit_box.damage_data = DamageData.fill(ins.hit_box.damage_data, {
			"damage": poison_damage,
			"type": GameTags.POISON_DAMAGE,
			"source": GameTags.EQUIP,
			"knockback": 0,
			"node": ins,
		})

		ins.global_position = doll.global_position
		ins.active_state()
		ExtensionHooks.notify(ExtensionHooks.on_visual_activated, [ins])
		ring = ins

func update_poison_damage():
	poison_damage = max(1, player.stats.bullet_damage * player.stats.equip_damage * damage_mult)

func _on_equip():
	now_cd = poison_cd
	damage_mult = 0.4
	player = get_tree().get_first_node_in_group("Player")
	update_poison_damage()
	var sprite_2d = kikyou_doll_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true
			doll = sprite_2d

func _setup():
	PlayerData.player_ability_changed_end.connect(update_poison_damage)
	GameEvents.global_time_count.connect(time_count)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	damage_mult += 0.15
