extends EquipItem


var equip_luck: int = 10
var equip_cd: int = 0
var can_shoot: bool = true

var launcher: Node

@onready var bullet_launcher: PackedScene = preload("res://scenes/update_item/player_bullet_launcher.tscn")

func time_count():
	if equip_cd > 0:
		equip_cd -= 1
		if equip_cd <= 0:
			can_shoot = true

func _on_equip():
	var ins = bullet_launcher.instantiate()
	ins.shoot_at_once = false
	ins.end_free = false
	get_tree().get_first_node_in_group("EquipLayer").add_child(ins)
	launcher = ins

	equip_luck = 10

func _setup():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.enemy_damage_taken.connect(shoot_bullet)
	GameEvents.global_time_count.connect(time_count)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	equip_luck += 10

func shoot_bullet(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data == null:
		return
	# 联机归属：只处理本机归属的伤害，避免 host 端因队友命中误触发本机分裂。
	var op: int = int(damage_data.owner_peer)
	if op != 0:
		if multiplayer == null or multiplayer.multiplayer_peer == null:
			return
		if op != multiplayer.get_unique_id():
			return
	if can_shoot == true and damage_data.damage_type.has(GameTags.BULLET_DAMAGE) and damage_data.source_type.has(GameTags.PLAYER) and !damage_data.flags.has("shrapnel_bullet"):
		var luck = randf_range(0, 200)
		if luck < (player.stats.luck + equip_luck):
			var enemy_body:= get_node_or_null(body_path)
			if enemy_body == null:
				return
			can_shoot = false
			launcher.flags.append("shrapnel_bullet")
			launcher.set("damage_data", damage_data)
			launcher.set("snapshot_damage", true)
			launcher.rotation = randf_range(-PI, PI)
			# 优先使用触发子弹的场景/池（仅 PlayerBullet 系；其它场景回退枪子弹）。
			var parent_scene: PackedScene = null
			var parent_pool: String = ""
			if damage_data.source_node != NodePath():
				var parent := get_tree().root.get_node_or_null(damage_data.source_node)
				if parent is PlayerBullet and parent.scene_file_path != "":
					parent_scene = load(parent.scene_file_path) as PackedScene
					if parent.get("pool_id") != null:
						parent_pool = str(parent.get("pool_id"))
			launcher.bullet = parent_scene if parent_scene != null else player.gun.bullet
			launcher.pool_id = parent_pool if parent_pool != "" else player.gun.bullet_pool_id
			launcher.bullet_count = 4
			launcher.bullet_arc = 270
			launcher.bullet_speed = player.stats.bullet_speed
			launcher.bullet_penetrate = player.stats.bullet_penetrate + 1
			launcher.collision_num = player.stats.collision_num
			launcher.global_position = enemy_body.global_position
			launcher.shoot_bullet()
			equip_cd = 2
