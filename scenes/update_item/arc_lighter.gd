extends EquipItem

# 电弧打火机：感电伤害命中「燃烧中」的敌人时引发爆燃，把燃烧层数直接补到当前上限。
#
# 触发：只认 SHOCK_DAMAGE（感电链命中），普通子弹/近战不会触发。
# 补层：走 enemy_buff_manager.apply_buff 公开入口（已存在条目时 value 不参与，这里传空 applier_stats
#       以保留原施加者的属性），每次 apply 会把 now_time 归零，所以爆燃同时刷新燃烧时长。
# 表现：复用 explosion_damage.tscn，但伤害/击退都给 0，只走 is_small_explosion() 的火环+音效。

const FIRE_BUFF: Buff = preload("res://resources/buff/enemy_buff/fire_dot.tres")
const FIRE_ID: String = "fire_dot"
const EXPLOSION_SCENE: PackedScene = preload("res://script/explosion_damage.tscn")

## 每目标冷却：一条链可能在同一帧扫过多个目标，冷却只防止同一目标被重复补层/重复刷表现。
const COOLDOWN_MS: int = 500
## 冷却字典上限：超过就清理已释放的实例 id。
const MAX_TRACKED: int = 64
## 单次补层上限（防御异常数据，正常只补 max_layer - layer 层）。
const MAX_FILL_LAYERS: int = 64
## 爆燃表现半径（explosion_damage.tscn 的 explosion_range 单位）。
const FX_RANGE: float = 2.5

var _next_ready: Dictionary = {}

func _setup() -> void:
	GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)

func _on_enemy_damage_taken(_final_damage: int, damage_data: DamageData, body_path: NodePath) -> void:
	if damage_data == null or not damage_data.damage_type.has(GameTags.SHOCK_DAMAGE):
		return
	var enemy: Node = get_node_or_null(body_path)
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	var current = manager.get("current_buff")
	if not (current is Dictionary):
		return
	var fire = current.get(FIRE_ID)
	if not (fire is Dictionary):
		return
	if bool(fire.get("stop", false)):
		return
	var layer: int = int(fire.get("layer", 0))
	var max_layer: int = int(fire.get("max_layer", 0))
	# 没有燃烧 / 已经满层：不重复触发，也不刷表现。
	if layer <= 0 or max_layer <= layer:
		return
	if not _combo_ready(enemy):
		return
	var fill: int = mini(max_layer - layer, MAX_FILL_LAYERS)
	for _i in fill:
		manager.apply_buff(FIRE_BUFF, [max_layer, 0.0, 0.0], item_id)
	_spawn_deflagration(enemy.global_position)
	_prune_tracking()

# 先占冷却再出效果：避免同帧多次链命中/后续燃烧 tick 把同一目标反复拉满。
func _combo_ready(enemy: Node) -> bool:
	var key: int = enemy.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if int(_next_ready.get(key, -1)) > now:
		return false
	_next_ready[key] = now + COOLDOWN_MS
	return true

func _prune_tracking() -> void:
	for key in _next_ready.keys():
		if not is_instance_id_valid(int(key)):
			_next_ready.erase(key)
	if _next_ready.size() <= MAX_TRACKED:
		return
	# Dictionary 保序：仍超限就丢最旧的键，保证真正封顶。
	for key in _next_ready.keys():
		if _next_ready.size() <= MAX_TRACKED:
			return
		_next_ready.erase(key)

func _spawn_deflagration(pos: Vector2) -> void:
	ProjectileSpawner.spawn_core(
		EXPLOSION_SCENE, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		pos, 0.0, Vector2.ZERO,
		true, false, true,
		Callable(),
		Callable(self, "_pre_activate_deflagration"),
		Callable(self, "_post_deflagration")
	)

func _pre_activate_deflagration(node: Node) -> void:
	node.explosion_range = FX_RANGE
	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": 0,
		"crit": false,
		"knockback": 0,
		"type": GameTags.FIRE_DAMAGE,
		"source": GameTags.EQUIP,
		"center": node.global_position,
	})

func _post_deflagration(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	node.is_small_explosion()
