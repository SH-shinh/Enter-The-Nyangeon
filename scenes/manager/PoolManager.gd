extends Node

var pool:Dictionary = {}

# 反向映射：instance_id -> pool_id。供 tree_exiting 自注销与 detach() 使用。
var _node_pool: Dictionary = {}

var num: int = 0

# 活跃敌人唯一真源：instance_id -> Node。
# 由敌人 active_state/idle_state/_exit_tree 登记，不再依赖战斗区探测框。
var _active_enemies: Dictionary = {}
var active_enemy_count: int = 0

# 按敌人 pool_id 的并发上限（场上活跃 + 待生成预占）；不在表内的敌人不设限。
const ENEMY_SPAWN_CAPS := {
	"tester_automaton_shield": 12,
	"droid_helmet_smg": 15,
	"lighttank_helmet": 4,
}
var _active_by_id: Dictionary = {}
var _pending_by_id: Dictionary = {}

const ENEMY_SPAWN_CAP := 80
const RECONCILE_TICK_INTERVAL := 10
var _spawn_stopped: bool = false
var _reconcile_tick: int = 0

# ---------------- 伤害数字自适应节流 ----------------
# 全局 tick 固定 0.1s（round_timer GlobalTimer），不可改；这里按 FPS 决定
# 每累计多少个 tick 才 flush 一次敌人伤害数字。FPS 越低，skip 越大。
const FPS_EMA_ALPHA := 0.2
const TEXT_RATE_DWELL_TICKS := 10
const TEXT_FPS_STEP2 := 35.0
const TEXT_FPS_STEP3 := 25.0
const TEXT_FPS_STEP4 := 18.0
const TEXT_FPS_RECOVER := 50.0
var _fps_ema: float = 60.0
var _text_tick_skip: int = 1
var _rate_dwell_ticks: int = 0

# ---------------- 特效频率节流 ----------------
# 特效最短间隔 = 基准间隔 * 手动系数(Game.effect_freq) * FPS 系数(只增间隔)。
# 固定类(枪口/命中火花/子弹烟/爆炸/地面涂装)按 category 全局一个间隔；
# 按实体类(燃烧/中毒/恶寒/策反/蒸汽)按 [category, body] 记录，互不挤占。
# 受击闪白独立于 effect_freq，走单独的 Game.hit_flash_freq（见 hit_flash_allowed）。
const EFFECT_FPS_STEP2 := 35.0
const EFFECT_FPS_STEP3 := 25.0
const EFFECT_FPS_STEP4 := 18.0
const FX_FOLLOW_BASE_MS := 200
const HIT_FLASH_BASE_MS := 60
# 各分类基准间隔（毫秒，= 最高档/默认；base_ms<0 时取此表）
const FX_BASE_MS := {
	&"muzzle_flash": 25,
	&"hit_spark": 40,
	&"bullet_smoke": 50,
	&"explosion": 50,
	&"floor_paint": 80,
}
var _fx_last_ms: Dictionary = {}
var _fx_body_last_ms: Dictionary = {}

var buff_box: Node

# buff 卡空闲栈：释放入栈、取用出栈，均为 O(1)（替代对 buff_box 的线性扫描）。
# 栈元素为 [instance_id, card]，出栈时即可按 id 从 set 清除，避免实例 id 复用导致漏栈。
var _idle_buff_cards: Array = []
var _idle_buff_set: Dictionary = {}

const IDLE_LIMITS := {
	"player_bullet": 150,
	"player_sniper_bullet": 80,
	"player_laser_bullet": 1,
	"shiro_missile": 60,
	"explosion_particles": 30,
	"explosion_smoke_particles": 30,
	"normal_bullet": 150,
	"player_explosion": 100,
	"small_explosion": 15,
	"big_explosion": 20,
	"enemy_bullet_1": 200,
	"enemy_bullet_2": 40,
	"enemy_missile_1": 20,
	"enemy_explosion": 20,
	"bullet_smoke_1": 30,
	"bullet_smoke_2": 30,
	"floating_text": 100,
	"fire": 30,
	"poison": 30,
	"chill": 30,
	"convert": 30,
	"sugar_cube_steam": 15,
	"player_flash": 5,
	"enemy_flash_1": 10,
	"summoned_flash_1": 5,
	"summon_level_display": 16,
	"floor_paint": 20,
	"enemy_fire_field": 100,
	"support_bullet": 60,
	"stone_bullet": 40,
	"cannon_bullet_1": 20,
	"cannon_flash_1": 10,
	"hit_flash": 10,
	"hit_flash_2": 10,
}

@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")

func _ready() -> void:
	GameEvents.global_time_count.connect(_on_global_time_count)

func get_buff_box():
	buff_box = get_tree().get_first_node_in_group("BuffBox")

func lear_buff_box():
	clear_idle_buff_cards()
	if buff_box != null:
		var group = buff_box.get_children()
		if !group.is_empty():
			for i in buff_box.get_children():
				i.queue_free()
			erase_pool("buff_box")

func erase_pool(body_name: String):
	if pool.has(body_name):
		var entry = pool[body_name]
		for n in entry.get("body", []):
			if n != null and is_instance_valid(n):
				_node_pool.erase(n.get_instance_id())
		pool.erase(body_name)

func clear_pool():
	pool.clear()
	_node_pool.clear()
	clear_active_enemies()

# ---------------- 活跃敌人登记 ----------------
# 敌人实体在 active_state / idle_state / _exit_tree 上报，O(1) 去重与删除。
func register_active_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	if _active_enemies.has(id):
		return
	_active_enemies[id] = enemy
	_add_active_id(enemy)
	active_enemy_count = _active_enemies.size()
	_refresh_spawn_state()

func unregister_active_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	if _active_enemies.erase(enemy.get_instance_id()):
		_sub_active_id(enemy)
		active_enemy_count = _active_enemies.size()
		_refresh_spawn_state()

# ---------------- 按 id 并发生成上限 ----------------
func _add_active_id(enemy: Node) -> void:
	var pid = enemy.get("pool_id")
	if pid != null and pid != "":
		_active_by_id[pid] = int(_active_by_id.get(pid, 0)) + 1

func _sub_active_id(enemy: Node) -> void:
	var pid = enemy.get("pool_id")
	if pid == null or pid == "":
		return
	var n: int = int(_active_by_id.get(pid, 0)) - 1
	if n <= 0:
		_active_by_id.erase(pid)
	else:
		_active_by_id[pid] = n

func _rebuild_active_by_id() -> void:
	_active_by_id.clear()
	for e in _active_enemies.values():
		if e != null and is_instance_valid(e):
			_add_active_id(e)

func get_active_count_by_id(id: String) -> int:
	return int(_active_by_id.get(id, 0))

func get_pending_count_by_id(id: String) -> int:
	return int(_pending_by_id.get(id, 0))

# 生成请求时预占名额：cap < 0 表示不设限；活跃 + 待生成 < cap 才允许并 +1 pending
func try_claim_spawn(id: String) -> bool:
	var cap: int = int(ENEMY_SPAWN_CAPS.get(id, -1))
	if cap < 0:
		return true
	if get_active_count_by_id(id) + get_pending_count_by_id(id) >= cap:
		return false
	_pending_by_id[id] = get_pending_count_by_id(id) + 1
	return true

func release_spawn_claim(id: String) -> void:
	if id == "":
		return
	var n: int = get_pending_count_by_id(id)
	if n <= 0:
		return
	if n == 1:
		_pending_by_id.erase(id)
	else:
		_pending_by_id[id] = n - 1

# 返回剔除失效 / 待机项之后的快照数组
func get_active_enemies() -> Array:
	_prune_active_enemies()
	return _active_enemies.values()

func get_random_active_enemy() -> Node:
	_prune_active_enemies()
	if _active_enemies.is_empty():
		return null
	return _active_enemies.values()[randi_range(0, _active_enemies.size() - 1)]

func clear_active_enemies() -> void:
	_active_enemies.clear()
	_active_by_id.clear()
	_pending_by_id.clear()
	active_enemy_count = 0
	_refresh_spawn_state()

func _prune_active_enemies() -> void:
	if _active_enemies.is_empty():
		return
	var dirty := false
	for id in _active_enemies.keys():
		var e = _active_enemies[id]
		if e == null or not is_instance_valid(e) or e.get("is_idle") == 1:
			_active_enemies.erase(id)
			dirty = true
	if dirty:
		_rebuild_active_by_id()
		active_enemy_count = _active_enemies.size()
		_refresh_spawn_state()

# 仅在跨过上限阈值时广播，避免每次增减都打断刷怪
func _refresh_spawn_state() -> void:
	var should_stop := active_enemy_count > ENEMY_SPAWN_CAP
	if should_stop == _spawn_stopped:
		return
	_spawn_stopped = should_stop
	if should_stop:
		GameEvents.emit_spawn_stop()
	else:
		GameEvents.emit_spawn_restart()

# 兼容旧调用名
func check_enemies() -> void:
	_prune_active_enemies()
	_refresh_spawn_state()

# 每 ~1s 用 "Enemy" 组全量校正，兜底任何漏报的登记/注销
func reconcile_active_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var next: Dictionary = {}
	for e in tree.get_nodes_in_group("Enemy"):
		if e == null or not is_instance_valid(e):
			continue
		if e.is_in_group("EnemyPart"):
			continue
		if e.get("is_idle") != null and e.is_idle == 1:
			continue
		next[e.get_instance_id()] = e
	if next.size() == _active_enemies.size():
		var same := true
		for id in next:
			if not _active_enemies.has(id):
				same = false
				break
		if same:
			return
	_active_enemies = next
	_rebuild_active_by_id()
	active_enemy_count = _active_enemies.size()
	_refresh_spawn_state()

func _on_global_time_count() -> void:
	_update_text_rate()
	_reconcile_tick += 1
	if _reconcile_tick >= RECONCILE_TICK_INTERVAL:
		_reconcile_tick = 0
		reconcile_active_enemies()

# 每 tick 平滑一次 FPS，按档位调整伤害数字 flush 跳过数。
# 35~55 为滞回带：保持当前档，避免低/高帧间来回抖（同时抑制飘字自身的反馈震荡）。
func _update_text_rate() -> void:
	_fps_ema = lerp(_fps_ema, float(Engine.get_frames_per_second()), FPS_EMA_ALPHA)
	if _rate_dwell_ticks > 0:
		_rate_dwell_ticks -= 1
		return
	var target: int = _text_tick_skip
	if _fps_ema < TEXT_FPS_STEP4:
		target = 4
	elif _fps_ema < TEXT_FPS_STEP3:
		target = 3
	elif _fps_ema < TEXT_FPS_STEP2:
		target = 2
	elif _fps_ema >= TEXT_FPS_RECOVER:
		target = 1
	if target != _text_tick_skip:
		_text_tick_skip = target
		_rate_dwell_ticks = TEXT_RATE_DWELL_TICKS

func get_text_tick_skip() -> int:
	var ceiling: int = _freq_ceiling_skip()
	if ceiling <= 0:
		return 0
	# 手动档是「上限」（设置项）：自适应只在此基础上再降（skip 更大 = 更疏），不会更密。
	return maxi(ceiling, _text_tick_skip)

# Game.damage_text_freq → 上限 skip：0=关 / 1=低(4) / 2=中(3) / 3=高(2) / 4=最高(1)。
func _freq_ceiling_skip() -> int:
	match Game.damage_text_freq:
		0:
			return 0
		1:
			return 4
		2:
			return 3
		3:
			return 2
		4:
			return 1
	return 1

# ---------------- 特效频率节流实现 ----------------
# 频率档位 → 手动间隔系数：0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1。
func _fx_manual_mult_of(freq: int) -> int:
	match freq:
		0:
			return 0
		1:
			return 4
		2:
			return 3
		3:
			return 2
	return 1

func _fx_manual_mult() -> int:
	return _fx_manual_mult_of(Game.effect_freq)

# FPS 系数（只增间隔，帧越低越大）。用伤害数字同一份 _fps_ema。
func _fx_fps_mult() -> int:
	if _fps_ema < EFFECT_FPS_STEP4:
		return 4
	if _fps_ema < EFFECT_FPS_STEP3:
		return 3
	if _fps_ema < EFFECT_FPS_STEP2:
		return 2
	return 1

func effect_freq_off() -> bool:
	return Game.effect_freq <= 0

func _fx_interval_ms(base_ms: int) -> int:
	var m: int = _fx_manual_mult()
	if m <= 0:
		return 0
	return base_ms * m * _fx_fps_mult()

# 固定类：全局每类最短间隔。base_ms<0 时取 FX_BASE_MS。true=允许播放。
func fx_allowed(category: StringName, base_ms: int = -1) -> bool:
	if effect_freq_off():
		return false
	var base: int = base_ms if base_ms >= 0 else int(FX_BASE_MS.get(category, 0))
	var interval: int = _fx_interval_ms(base)
	if interval <= 0:
		return true
	var now: int = Time.get_ticks_msec()
	if now - int(_fx_last_ms.get(category, -1000000000)) < interval:
		return false
	_fx_last_ms[category] = now
	return true

# 按实体类：每 [category, body] 最短间隔。base_ms<0 时取 FX_BASE_MS。true=允许播放。
func fx_allowed_body(category: StringName, body: Node, base_ms: int = -1) -> bool:
	if effect_freq_off():
		return false
	if body == null or not is_instance_valid(body):
		return true
	var base: int = base_ms if base_ms >= 0 else int(FX_BASE_MS.get(category, 0))
	var interval: int = _fx_interval_ms(base)
	if interval <= 0:
		return true
	var key: String = "%s:%d" % [category, body.get_instance_id()]
	var now: int = Time.get_ticks_msec()
	if now - int(_fx_body_last_ms.get(key, -1000000000)) < interval:
		return false
	_fx_body_last_ms[key] = now
	return true

# 受击闪白（独立设置 Game.hit_flash_freq，按实体，与 effect_freq 解耦）。true=允许闪。
func hit_flash_allowed(body: Node) -> bool:
	if Game.hit_flash_freq <= 0:
		return false
	if body == null or not is_instance_valid(body):
		return true
	var m: int = _fx_manual_mult_of(Game.hit_flash_freq)
	if m <= 0:
		return false
	var interval: int = HIT_FLASH_BASE_MS * m * _fx_fps_mult()
	var key: String = "hit_flash_white:%d" % body.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if now - int(_fx_body_last_ms.get(key, -1000000000)) < interval:
		return false
	_fx_body_last_ms[key] = now
	return true

# 跟随类是否允许：同一 body 已有该类 FX 在飞则跳过（防叠加），再走每 body 间隔。
func _fx_follow_allowed(body_name: String, body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return true
	var entry = pool.get(body_name)
	if entry != null:
		for n in entry["body"]:
			if n != null and is_instance_valid(n) and n.get("is_idle") == 0 and n.get("target") == body:
				return false
	return fx_allowed_body(StringName(body_name), body, FX_FOLLOW_BASE_MS)

func add_pool(body_name: String, body: Node):
	if body == null:
		return
	var entry = pool.get(body_name)
	if entry == null:
		pool[body_name] = {
			"resource": body_name,
			"body": [body],
			"index": 0,
			"limit": IDLE_LIMITS.get(body_name, -1),
			"set": {body: true},
			"idle": ([body] if body.get("is_idle") == 1 else [])
		}
	elif entry["set"].has(body):
		return
	else:
		entry["body"].push_back(body)
		entry["set"][body] = true
		if body.get("is_idle") == 1:
			_entry_idle(entry).push_back(body)
	_register_node_pool(body, body_name)

func get_buff_pool():
	while not _idle_buff_cards.is_empty():
		var entry = _idle_buff_cards.pop_back()
		_idle_buff_set.erase(entry[0])
		var card = entry[1]
		if card != null and is_instance_valid(card) and card.get("is_idle") == 1:
			return card
	return _scan_buff_box_idle()

# 兜底：栈空/无有效项时退回扫描 buff_box（正确性保底）
func _scan_buff_box_idle():
	if buff_box == null or not is_instance_valid(buff_box):
		return null
	for child in buff_box.get_children():
		if child.get("is_idle") == 1:
			return child
	return null

# buff 卡释放回池时调用；按 instance_id 去重，避免同一张卡重复入栈
func push_idle_buff_card(card: Node):
	if card == null or not is_instance_valid(card):
		return
	var id: int = card.get_instance_id()
	if _idle_buff_set.has(id):
		return
	_idle_buff_set[id] = true
	_idle_buff_cards.push_back([id, card])

func clear_idle_buff_cards():
	_idle_buff_cards.clear()
	_idle_buff_set.clear()

func sort_pool(_body_name: String):
	pass

# ---------------- 归属登记 / 自注销 ----------------
func _register_node_pool(body: Node, body_name: String) -> void:
	_node_pool[body.get_instance_id()] = body_name
	if not body.has_meta("_pool_exit_connected"):
		body.set_meta("_pool_exit_connected", true)
		body.tree_exiting.connect(_on_pooled_node_exit.bind(body))

func _on_pooled_node_exit(body: Node) -> void:
	_remove_node_from_pool(body)

# 从所属池移除（body/set/idle 缓存/反向映射）。池空则删条目。
func _remove_node_from_pool(body: Node) -> void:
	if body == null:
		return
	var iid: int = body.get_instance_id()
	var pid = _node_pool.get(iid)
	if pid == null:
		return
	_node_pool.erase(iid)
	var entry = pool.get(pid)
	if entry == null:
		return
	var arr: Array = entry["body"]
	var idx: int = arr.find(body)
	if idx != -1:
		arr.remove_at(idx)
	entry["set"].erase(body)
	_entry_idle(entry).erase(body)
	if arr.is_empty():
		pool.erase(pid)
	else:
		entry["index"] = wrapi(int(entry.get("index", 0)), 0, arr.size())

# 公开：把节点从对象池剥离（纯表现副本等不再被玩法逻辑复用时调用）。
func detach(body: Node) -> void:
	_remove_node_from_pool(body)

# 静默回收：优先无副作用变体，避免强制回收触发爆炸等玩法副作用。
func _recycle(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("deactivate_silent"):
		body.deactivate_silent()
	elif body.has_method("idle_state"):
		body.idle_state()

func _entry_idle(entry) -> Array:
	if not entry.has("idle"):
		entry["idle"] = []
	return entry["idle"]

# 从空闲缓存弹出一个仍有效且确为空闲的节点（失效/已激活项丢弃）。
func _pop_idle(entry):
	var cache: Array = _entry_idle(entry)
	var tset = entry["set"]
	while not cache.is_empty():
		var n = cache.pop_back()
		if n != null and is_instance_valid(n) and tset.has(n) and n.get("is_idle") == 1:
			return n
	return null

# 整表扫描并把所有空闲节点回填缓存（供下次 O(1) 取用）。
func _scan_fill_idle(entry) -> void:
	var cache: Array = _entry_idle(entry)
	cache.clear()
	var tset = entry["set"]
	for n in entry["body"]:
		if n != null and is_instance_valid(n) and tset.has(n) and n.get("is_idle") == 1:
			cache.push_back(n)

# 取池：空闲优先（缓存→整表扫描）；无空闲且未达上限返回 null（调用方新建）；
# 满额才静默回收轮转槽位。绝不在存在空闲节点时强收活跃节点。
func get_pool(body_name: String):
	var entry = pool.get(body_name)
	if entry == null:
		return null
	var body: Array = entry["body"]
	if body.is_empty():
		return null
	var n = _pop_idle(entry)
	if n != null:
		return n
	_scan_fill_idle(entry)
	n = _pop_idle(entry)
	if n != null:
		return n
	var cap: int = int(entry["limit"])
	if cap < 0 or body.size() < cap:
		return null
	var idx: int = wrapi(int(entry["index"]), 0, body.size())
	var victim = body[idx]
	entry["index"] = wrapi(idx + 1, 0, body.size())
	_recycle(victim)
	return victim

# 只取空闲（金币等自管计数的池必须用此，避免强收活跃节点丢值）。
func get_pool_idle(body_name: String):
	var entry = pool.get(body_name)
	if entry == null:
		return null
	var n = _pop_idle(entry)
	if n != null:
		return n
	_scan_fill_idle(entry)
	return _pop_idle(entry)

# ---------------- 池统计 ----------------
func pool_total(body_name: String) -> int:
	var entry = pool.get(body_name)
	return 0 if entry == null else (entry["body"] as Array).size()

func pool_idle_count(body_name: String) -> int:
	var entry = pool.get(body_name)
	if entry == null:
		return 0
	var count: int = 0
	for n in entry["body"]:
		if n != null and is_instance_valid(n) and n.get("is_idle") == 1:
			count += 1
	return count

func pool_active_count(body_name: String) -> int:
	return pool_total(body_name) - pool_idle_count(body_name)

func pool_stats() -> Dictionary:
	var out: Dictionary = {}
	for id in pool.keys():
		out[id] = {
			"total": pool_total(id),
			"idle": pool_idle_count(id),
			"active": pool_active_count(id),
			"limit": pool[id]["limit"],
		}
	return out

# 统一的对象池特效入口：取池中特效跟随 body，池空或全忙则实例化新节点。
# scene 需继承 PooledFollowFx（提供 is_idle / follow_body / play_anim）。
func spawn_fx(body_name: String, scene: PackedScene, body: Node, layer_group: String = "SELayer") -> Node2D:
	if effect_freq_off():
		return null
	if not _fx_follow_allowed(body_name, body):
		return null
	var fx: Node2D = get_pool(body_name)
	if fx == null or fx.is_idle == 0:
		fx = scene.instantiate() as Node2D
		get_tree().get_first_node_in_group(layer_group).add_child(fx)
	fx.follow_body(body)
	fx.play_anim()
	return fx

func add_text(text: String,text_position: Vector2, text_color: Color, text_size: int):
	
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	floating_text.set_style(text_color, text_size)
	floating_text.global_position = text_position + (Vector2.UP * randf_range(15,25)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(text)
