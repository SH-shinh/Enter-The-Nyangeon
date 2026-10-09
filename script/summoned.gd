class_name Summoned
extends CharacterBody2D

signal self_is_idle
signal summon_level_changed(state: Dictionary)

const LEVEL_DISPLAY_PATH := "res://scenes/summoned/summon_level_display.tscn"
const LEVEL_DISPLAY_ANCHOR := "%LevelDisplayAnchor"

@export var stats: SummonedStats
@export var gun: Node
@export var level_display_height: float = 56.0 # 无 LevelDisplayAnchor 时的头顶高度兜底

@onready var summoned_buff_manager: Node = $SummonedBuffManager

# 固有等级系统状态（等级/经验属于召唤物自身；来源无关）
var summon_level: int = 1
var summon_exp: int = 0
var summon_exp_level_add: int = 0
var summon_exp_level_count: int = 0
var _level_display: Node = null

var can_move: bool = true
var ACCELERATION: float
var player: Node
var spawn_point: Vector2 = Vector2(704, 448)
var enemy_body: Array = []
var hurt_dir: Vector2
var hurt_knockback: int
var direction: Vector2
var is_idle: int = 0

# 排序合帧：同帧多次 enter/exit 只排一次（deferred），避免每事件全量重排
var _sort_dirty: bool = false

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	_setup_level_display()
	ExtensionHooks.notify(ExtensionHooks.on_summoned_spawned, [self, str(scene_file_path)])

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_summoned_despawned, [self])
	self_is_idle.emit()
	visible = false
	global_position = Vector2(10000, -10000)
	is_idle = 1
	clear_buffs()
	_release_level_display()
	_reset_summon_level()
	process_mode = Node.PROCESS_MODE_DISABLED

func _exit_tree():
	_release_level_display()

# ---------------- 固有等级系统 ----------------

func _exp_to_next() -> int:
	if stats == null:
		return 1
	return maxi(1, stats.level_up_exp_base + summon_exp_level_add)

func get_summon_level_state() -> Dictionary:
	return {
		"level": summon_level,
		"exp": summon_exp,
		"exp_level_add": summon_exp_level_add,
		"exp_to_next": _exp_to_next(),
		"max_level": (stats.max_level if stats != null else 0),
	}

func _reset_summon_level() -> void:
	summon_level = 1
	summon_exp = 0
	summon_exp_level_add = 0
	summon_exp_level_count = 0

func _at_max_level() -> bool:
	return stats != null and stats.max_level > 0 and summon_level >= stats.max_level

# 通用来源入口：喂经验（amount>1 支持连升）。
# 权威端（本地拥有）真正结算；远端镜像由 mod 经 summoned_upgrade_interceptor 转发给拥有者。
func add_summon_exp(amount: int, source_id := &"", damage_add_override: int = 0) -> Dictionary:
	if amount <= 0 or stats == null or not stats.level_enabled:
		return {}
	if ExtensionHooks.intercept(ExtensionHooks.summoned_upgrade_interceptor, [self, amount, source_id, damage_add_override]):
		return {}
	var gained: int = 0
	while gained < amount:
		if _at_max_level():
			break
		gained += 1
		summon_exp += 1
		if summon_exp >= _exp_to_next():
			summon_exp = 0
			summon_level += 1
			summon_exp_level_count += 1
			if stats.level_exp_growth > 0 and summon_exp_level_count >= stats.level_exp_growth:
				summon_exp_level_count = 0
				summon_exp_level_add += 1
			_apply_level_up(damage_add_override)
	var state := get_summon_level_state()
	summon_level_changed.emit(state)
	return state

# 道具/技能便捷：直接加若干级
func add_summon_level(delta: int, source_id := &"") -> Dictionary:
	if delta <= 0:
		return {}
	return set_summon_level(summon_level + delta, source_id)

# 道具/技能便捷：直接设定等级
func set_summon_level(level: int, source_id := &"") -> Dictionary:
	if stats == null or not stats.level_enabled:
		return {}
	var target: int = maxi(1, level)
	if stats.max_level > 0:
		target = mini(target, stats.max_level)
	if target == summon_level:
		return get_summon_level_state()
	var diff: int = target - summon_level
	if ExtensionHooks.intercept(ExtensionHooks.summoned_upgrade_interceptor, [self, diff, source_id, 0]):
		return {}
	summon_level = target
	summon_exp = 0
	if diff > 0 and stats.level_damage_add != 0:
		stats.summoned_damage_add += stats.level_damage_add * diff
		stats.update_body_ability()
	var state := get_summon_level_state()
	summon_level_changed.emit(state)
	return state

# 每级加成：来源覆盖（damage_add_override>0）优先，否则固有 stats.level_damage_add
func _apply_level_up(damage_add_override: int) -> void:
	if stats == null:
		return
	var add: int = damage_add_override if damage_add_override > 0 else stats.level_damage_add
	if add == 0:
		return
	stats.summoned_damage_add += add
	stats.update_body_ability()

# 镜像端：应用拥有者广播的等级状态（仅显示，不重复结算数值）
func apply_network_summon_level_state(state: Dictionary) -> void:
	if not (state is Dictionary):
		return
	summon_level = maxi(1, int(state.get("level", summon_level)))
	summon_exp = maxi(0, int(state.get("exp", summon_exp)))
	summon_exp_level_add = maxi(0, int(state.get("exp_level_add", summon_exp_level_add)))
	summon_level_changed.emit(get_summon_level_state())

# 联机：拥有者端应用远端攻击方的友方近战击退（不走伤害/命中反馈）
func apply_network_melee_knockback(force: int, dir: Vector2) -> void:
	if force <= 0:
		return
	for n in find_children("*", "Node", true, false):
		if n is SummonedHealthComponent:
			n.apply_network_melee_knockback(force, dir)
			return

# 显示高度锚点：优先 LevelDisplayAnchor（可挂在精灵下随跳跃移动），否则根节点上方兜底高度
func get_level_display_position() -> Vector2:
	var anchor := get_node_or_null(LEVEL_DISPLAY_ANCHOR)
	if anchor is Node2D:
		return (anchor as Node2D).global_position
	return global_position + Vector2(0.0, -level_display_height)

func _setup_level_display() -> void:
	if stats == null or not stats.level_enabled:
		return
	var sel := get_tree().get_first_node_in_group("SELayer")
	if sel == null:
		return
	var d: Node = PoolManager.get_pool("summon_level_display")
	if d == null or d.get("is_idle") != 1:
		var scene := load(LEVEL_DISPLAY_PATH) as PackedScene
		if scene == null:
			return
		d = scene.instantiate()
		sel.add_child(d)
	_level_display = d
	if d.has_method("bind"):
		d.call("bind", self)

func _release_level_display() -> void:
	if _level_display != null and is_instance_valid(_level_display):
		if _level_display.has_method("idle_state"):
			_level_display.call("idle_state")
	_level_display = null


func clear_buffs():
	summoned_buff_manager.clear_all_buff()

func _on_area_2d_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and body.get("faction") != Faction.PLAYER_SIDE and not enemy_body.has(body):
		enemy_body.append(body)
		if body.has_signal("converted_changed") and not body.converted_changed.is_connected(_on_target_converted):
			body.converted_changed.connect(_on_target_converted)
		_mark_sort_dirty()

func _on_area_2d_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	var removed := false
	if body.is_in_group("Enemy") and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		removed = true
	if body.has_signal("converted_changed") and body.converted_changed.is_connected(_on_target_converted):
		body.converted_changed.disconnect(_on_target_converted)
	if removed:
		_mark_sort_dirty()

# 剔除已释放目标，供 sort_enemy 与各 enemy_body[0] 消费点复用
func _prune_enemy_body() -> void:
	for i in range(enemy_body.size() - 1, -1, -1):
		if enemy_body[i] == null or not is_instance_valid(enemy_body[i]):
			enemy_body.remove_at(i)

func _on_target_converted(_converted: bool):
	var removed := false
	for i in range(enemy_body.size() - 1, -1, -1):
		var e = enemy_body[i]
		if e == null or not is_instance_valid(e) or e.get("faction") == Faction.PLAYER_SIDE:
			enemy_body.remove_at(i)
			removed = true
	if removed:
		_mark_sort_dirty()

func _mark_sort_dirty():
	if _sort_dirty:
		return
	_sort_dirty = true
	sort_enemy.call_deferred()

func sort_enemy():
	_sort_dirty = false
	_prune_enemy_body()
	if enemy_body.is_empty():
		return
	var origin := global_position
	# 平方距离比较，省去每次 sqrt
	enemy_body.sort_custom(func(x, y):
		return x.global_position.distance_squared_to(origin) < y.global_position.distance_squared_to(origin))

func move(_gravity: float, delta: float, accel: float, max_speed: float) -> void:
	velocity.x = move_toward(velocity.x, direction.x * max_speed, accel * delta)
	velocity.y = move_toward(velocity.y, direction.y * max_speed, accel * delta)
	move_and_slide()
	var collision = get_last_slide_collision()
	if collision and velocity.length() > (stats.summoned_speed * 2):
		velocity = velocity.bounce(collision.get_normal()) * 0.4

func apply_knockback(v: Vector2):
	if v != Vector2.ZERO:
		velocity = v

func tick_physics(_state: int, _delta: float) -> void:
	pass

func get_next_state(state: int) -> int:
	return state

func transition_state(_from: int, _to: int) -> void:
	pass
