extends SupportAS

signal explosion_end

# 轰炸发数基础值/上限：EX 持续时间倍率按此缩放序列长度。
const BASE_EXPLOSION_COUNT: int = 50
const MAX_EXPLOSION_COUNT: int = 200
# 落点覆盖椭圆半径（相对地图中心）。固定设计值：不接倍率、不受玩家数值影响。
const BASE_COVERAGE: Vector2 = Vector2(888, 440)

@export var explosion_pack: PackedScene
@export var explosion_damage: int = 500
## 单发爆炸半径基础值（explosion_range 单位，1 单位 = 10px 碰撞半径）。只受支援 EX 范围倍率影响。
@export var blast_range_base: float = 7.0

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
	
	player = PlayerRef.ensure(self, player)
	
	var center = Vector2(704, 448)
	var rx := int(BASE_COVERAGE.x)  # 从中心到右顶点距离（固定，不接倍率）
	var ry := int(BASE_COVERAGE.y)  # 从中心到上/下顶点距离（固定，不接倍率）

	var explosion_points = generate_explosion_positions(_explosion_count(), rx, ry, center, 2.0)
	
	for i in explosion_points.size():
		add_explosion(explosion_points[i])
		explosion_num += 1
		if explosion_num > 4:
			explosion_num = 0
			timer.start()
			await timer.timeout
	explosion_end.emit()

## 本次轰炸发数：持续时间倍率只缩放序列长度（duration_add 对序列型 EX 不适用）。
func _explosion_count() -> int:
	return clampi(int(round(float(BASE_EXPLOSION_COUNT) * SupportData.get_ex_duration_mult())), 1, MAX_EXPLOSION_COUNT)

## 单发爆炸半径：支援范围倍率 × 支援基础值，与玩家 stats.explosion_range 解耦。
func _blast_range() -> float:
	return maxf(0.1, blast_range_base * SupportData.get_ex_range_mult())

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
	var p := PlayerRef.ensure(self, player)
	player = p
	if p == null:
		return
	node.damage_data = DamageData.fill(node.damage_data, {
		"knockback": max(p.stats.bullet_knockback, 1),
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.EQUIP,
		"node": self,
	})
	var luck = randf_range(0, 100)
	var base_damage: float = float(explosion_damage) * SupportData.get_ex_power_mult()
	if luck < p.stats.critical_luck:
		node.damage_data.base_damage = max(1, (base_damage + p.stats.bullet_damage * 0.6) * p.stats.global_damage * p.stats.critical_damage * p.stats.equip_damage)
		node.damage_data.is_crit = true
	else:
		node.damage_data.base_damage = max(1, (base_damage + p.stats.bullet_damage * 0.6) * p.stats.global_damage * p.stats.equip_damage)
		node.damage_data.is_crit = false
	node.explosion_range = _blast_range()

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
