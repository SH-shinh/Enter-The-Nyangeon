extends SupportAS

signal explosion_end

@export var explosion_pack: PackedScene
@export var explosion_damage: int = 500

@onready var timer: Timer = $Timer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer

var player: Node
var explosion_num: int = 0

func _on_ready() -> void:
	explosion_end.connect(skill_end)
	animation_player_2.animation_finished.connect(anim_end)

func _on_skill_active() -> void:
	animation_player.play("loop")
	animation_player_2.play("attack_anim")

func anim_end(_anim_name: String):
	explosion_num = 0
	animation_player.play("RESET")
	animation_player_2.play("RESET")
	audio_stream_player.stop()

func explosion_to_map():
	
	if player == null:
		player = get_tree().get_first_node_in_group("Player")
	
	var center = Vector2(704, 448)
	var rx = 888  # 从中心到右顶点距离
	var ry = 440  # 从中心到上/下顶点距离

	var explosion_points = generate_explosion_positions(50, rx, ry, center, 2.0)
	
	for i in explosion_points.size():
		add_explosion(explosion_points[i])
		explosion_num += 1
		if explosion_num > 4:
			explosion_num = 0
			timer.start()
			await timer.timeout
	explosion_end.emit()

func add_explosion(point: Vector2):
	ProjectileSpawner.spawn_core(
		explosion_pack, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		point, 0.0, Vector2.ZERO,
		true, false, true,
		Callable(self, "_configure_explosion"),
		Callable(self, "_pre_activate_explosion"),
		Callable(self, "_post_explosion")
	)

func _configure_explosion(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"knockback": max(player.stats.bullet_knockback, 1),
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.EQUIP,
		"node": self,
	})
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		node.damage_data.base_damage = max(1, (explosion_damage + player.stats.bullet_damage * 0.6) * player.stats.global_damage * player.stats.critical_damage * player.stats.equip_damage)
		node.damage_data.is_crit = true
	else:
		node.damage_data.base_damage = max(1, (explosion_damage + player.stats.bullet_damage * 0.6) * player.stats.global_damage * player.stats.equip_damage)
		node.damage_data.is_crit = false
	node.explosion_range = 7 * max(1, player.stats.explosion_range * 0.3)

func _pre_activate_explosion(node: Node) -> void:
	node.damage_data.hit_box_center = node.global_position

func _post_explosion(node: Node) -> void:
	node.is_explosion()

func generate_explosion_positions(num_points: int, radius_x: int, radius_y: int, center: Vector2, random_offset: float = 20.0) -> Array:
	var points = []
	var candidates = []
	var step = max(1, int(sqrt(float(radius_x * radius_y) / float(num_points))))
	
	# 生成候选点
	for x in range(center.x - radius_x, center.x + radius_x + 1, step):
		for y in range(center.y - radius_y, center.y + radius_y + 1, step):
			var dx = x - center.x
			var dy = y - center.y
			if abs(dx) * radius_y + abs(dy) * radius_x <= radius_x * radius_y:
				candidates.append(Vector2(x, y))
	
	# 随机选择
	candidates.shuffle()
	var selected = candidates.slice(0, min(num_points, candidates.size() - 1))
	
	# 添加随机偏移
	for p in selected:
		var offset_x = randf_range(-random_offset, random_offset)
		var offset_y = randf_range(-random_offset, random_offset)
		points.append(p + Vector2(offset_x, offset_y))
	
	# ===== 关键修改：按左上到右下排序 =====
	# 左上角 x+y 最小，右下角 x+y 最大
	points.sort_custom(func(a, b): 
		return (a.x + a.y) < (b.x + b.y)
	)
	
	return points
