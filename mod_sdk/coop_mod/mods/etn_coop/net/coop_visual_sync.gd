extends RefCounted

## CoopVisualSync：远程视觉弹/特效的创建、池化与伤害禁用。
## 关键点：
##  - 视觉弹从「本体 gameplay 池」中移除，避免被本地生成逻辑复用（其碰撞已被清零）。
##  - 视觉弹清空 collision layer/mask、关 monitoring、禁 shape，纯表现，不结算伤害。
##  - 发送端只在生成时广播；视觉弹靠自身 kill_time 自然回池。

const MAX_PER_SCENE: int = 180
const EFFECT_POOL_MAX: int = 24

var _pool: Dictionary = {}        # scene_path -> Array[Node]（子弹）
var _effect_pool: Dictionary = {} # scene_path -> Array[Node]（可复用特效：有 is_idle）
var _by_sync_id: Dictionary = {}  # sync_id -> Node
var _ended: Dictionary = {}       # sync_id -> true（已结束，防止迟到的 spawn 复活）
var _ended_order: Array[String] = []
var _by_effect_id: Dictionary = {} # effect_id -> Node（特效通道回收句柄）
var _ended_effect: Dictionary = {} # effect_id -> true（防止迟到的 spawn 复活）
var _ended_effect_order: Array[String] = []
var effects_spawned: int = 0


func reset() -> void:
	for bodies in _pool.values():
		for b in bodies:
			if b != null and is_instance_valid(b):
				b.queue_free()
	_pool.clear()
	for bodies in _effect_pool.values():
		for b in bodies:
			if b != null and is_instance_valid(b):
				b.queue_free()
	_effect_pool.clear()
	_by_sync_id.clear()
	_ended.clear()
	_ended_order.clear()
	_by_effect_id.clear()
	_ended_effect.clear()
	_ended_effect_order.clear()
	effects_spawned = 0


func spawn_visual_bullet(tree: SceneTree, scene_path: String, position: Vector2, rotation: float, speed: float, bullet_scale: Vector2, kill_time: int, sync_id: String, properties: Dictionary = {}, pre_method: String = "", method_name: String = "active_state") -> void:
	if tree == null or scene_path == "":
		return
	if sync_id != "" and _ended.has(sync_id):
		return
	if sync_id != "" and _by_sync_id.has(sync_id):
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var root := tree.get_first_node_in_group("BulletRoot")
	if root == null:
		return
	var bullet := _acquire(scene, scene_path, sync_id)
	if bullet == null:
		return
	var add_bullet: bool = bullet.get_parent() == null
	bullet.set_meta("remote_visual", true)
	if sync_id != "":
		bullet.set_meta("visual_sync_id", sync_id)
		_by_sync_id[sync_id] = bullet
	bullet.global_position = position
	bullet.global_rotation = rotation
	bullet.scale = bullet_scale
	if bullet.get("speed") != null:
		bullet.speed = speed
	if bullet.get("kill_time") != null:
		bullet.kill_time = kill_time
	# 白名单弹道属性
	var pr = properties.get("pr", null)
	if pr is Dictionary:
		for k in pr.keys():
			bullet.set(str(k), pr[k])
	if add_bullet:
		root.add_child(bullet)
		_remove_from_gameplay_pools(bullet, scene_path)
	# 对齐联机版：先 pre_method、再 method，最后禁伤
	if pre_method != "" and bullet.has_method(pre_method):
		bullet.call(pre_method)
	if method_name != "" and bullet.has_method(method_name):
		bullet.call(method_name)
	_disable_damage(bullet)
	# 敌方弹对本地玩家开放伤害（伤害洞）：只命中玩家、不命中其它
	if bool(properties.get("eb", false)):
		_open_player_damage_hole(bullet, int(properties.get("dmg", 1)), int(properties.get("kb", 0)))


func forget(sync_id: String) -> void:
	_by_sync_id.erase(sync_id)


# 收到「提前终止」：立即隐藏/回池，并标记 ended 防止迟到 spawn 复活。
func despawn_visual_bullet(sync_id: String) -> void:
	if sync_id == "":
		return
	if not _ended.has(sync_id):
		_ended[sync_id] = true
		_ended_order.append(sync_id)
		while _ended_order.size() > 4096:
			var old: String = _ended_order.pop_front()
			_ended.erase(old)
	if not _by_sync_id.has(sync_id):
		return
	var b = _by_sync_id[sync_id]
	_by_sync_id.erase(sync_id)
	_visual_idle(b)


# 特效通道（无 velocity 的长期存在物，如 player_laser_beam/laser_launcher）按 effect_id 回收
func despawn_visual_effect(effect_id: String) -> void:
	if effect_id == "":
		return
	if not _ended_effect.has(effect_id):
		_ended_effect[effect_id] = true
		_ended_effect_order.append(effect_id)
		while _ended_effect_order.size() > 4096:
			var old: String = _ended_effect_order.pop_front()
			_ended_effect.erase(old)
	if not _by_effect_id.has(effect_id):
		return
	var e = _by_effect_id[effect_id]
	_by_effect_id.erase(effect_id)
	if e != null and is_instance_valid(e):
		e.remove_meta("_coop_effect_id")
		_visual_idle(e)


# 远端纯视觉克隆销毁：优先专用 visual_idle_state（跳过爆炸等副作用），否则回退 idle_state
func _visual_idle(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("visual_idle_state"):
		node.call("visual_idle_state")
	elif node.has_method("idle_state"):
		node.call("idle_state")
	else:
		node.queue_free()


func total() -> int:
	var t: int = 0
	for bodies in _pool.values():
		t += bodies.size()
	return t


func effect_count() -> int:
	return effects_spawned


func active_count() -> int:
	return _by_sync_id.size()


# 远程视觉特效（爆炸/范围/一次性粒子）：不池化，安全超时释放，纯表现无伤害。
func spawn_visual_effect(tree: SceneTree, scene_path: String, position: Vector2, rotation: float, effect_scale: Vector2, root_group: String, method_name: String, properties: Dictionary, effect_id: String = "") -> void:
	if tree == null or scene_path == "":
		return
	if effect_id != "" and _ended_effect.has(effect_id):
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var group: String = root_group if root_group != "" else "SELayer"
	var root := tree.get_first_node_in_group(group)
	if root == null:
		return
	var effect: Node = _acquire_effect(scene_path)
	if effect == null:
		effect = scene.instantiate()
	if effect.get_parent() == null:
		root.add_child(effect)
	elif effect.get_parent() != root:
		effect.get_parent().remove_child(effect)
		root.add_child(effect)
	effect.set_meta("remote_visual", true)
	if effect_id != "":
		var old_eid: String = str(effect.get_meta("_coop_effect_id", ""))
		if old_eid != "" and _by_effect_id.get(old_eid) == effect:
			_by_effect_id.erase(old_eid)
		_by_effect_id[effect_id] = effect
		effect.set_meta("_coop_effect_id", effect_id)
	effects_spawned += 1
	if effect is Node2D:
		(effect as Node2D).global_position = position
		(effect as Node2D).global_rotation = rotation
	effect.scale = effect_scale
	for k in properties.keys():
		effect.set(str(k), properties[k])
	_remove_effect_from_gameplay_pools(effect)
	_disable_damage(effect)
	if method_name != "" and effect.has_method(method_name):
		effect.call(method_name)
	# 敌方激光等：对本地玩家开放"伤害洞"（仅表现端、只命中玩家）
	if effect.has_method("open_network_player_damage_hole"):
		effect.call("open_network_player_damage_hole")
	# 可复用特效（有 is_idle，如爆炸/烟）入池复用；否则延时释放
	if effect.get("is_idle") != null:
		_track_effect(scene_path, effect)
	elif effect_id == "":
		# 无 effect_id 的一次性特效：安全超时释放；带 id 者等 despawn 广播回收，避免远端早于本地消失
		_queue_free_after(tree, effect, 6.0)


# 取可复用空闲特效；无则返回 null（由调用方实例化）
func _acquire_effect(scene_path: String) -> Node:
	var arr: Array = _effect_pool.get(scene_path, [])
	if arr.is_empty():
		return null
	var valid: Array = []
	for b in arr:
		if b != null and is_instance_valid(b):
			valid.append(b)
	_effect_pool[scene_path] = valid
	for b in valid:
		if b.get("is_idle") != null and int(b.is_idle) == 1:
			return b
	if valid.size() >= EFFECT_POOL_MAX:
		for b in valid:
			_visual_idle(b)
			return b
	return null


func _track_effect(scene_path: String, effect: Node) -> void:
	if not _effect_pool.has(scene_path):
		_effect_pool[scene_path] = []
	var arr: Array = _effect_pool[scene_path]
	if not arr.has(effect):
		arr.append(effect)


func _remove_effect_from_gameplay_pools(effect: Node) -> void:
	var pid: String = ""
	if effect.get("pool_id") != null:
		pid = str(effect.pool_id)
	# 爆炸场景无 pool_id 字段，按场景路径映射其本体池名，避免新实例污染 gameplay 池
	if pid == "":
		var sp: String = str(effect.scene_file_path)
		if sp.contains("small_explosion"):
			pid = "small_explosion"
		elif sp.contains("explosion.tscn"):
			pid = "big_explosion"
		elif sp.contains("floating_text"):
			pid = "floating_text"
	if pid == "" or not PoolManager.pool.has(pid):
		return
	var entry: Dictionary = PoolManager.pool[pid]
	var bodies: Array = entry.get("body", [])
	bodies.erase(effect)
	var size: int = bodies.size()
	if size <= 0:
		PoolManager.pool.erase(pid)
	else:
		entry["index"] = wrapi(int(entry.get("index", 0)), 0, size)


func _queue_free_after(tree: SceneTree, node: Node, seconds: float) -> void:
	if node == null or seconds <= 0.0:
		return
	# 用 WeakRef，避免 lambda 直接捕获 Node；节点被提前释放（如测试房重置）后定时器触发，
	# Godot 会报 "Lambda capture was freed"（即便函数内 is_instance_valid 也已晚）
	var wr: WeakRef = weakref(node)
	tree.create_timer(seconds).timeout.connect(func():
		var n = wr.get_ref()
		if n != null:
			(n as Node).queue_free()
	)


func _acquire(scene: PackedScene, scene_path: String, sync_id: String) -> Node:
	if sync_id != "" and _by_sync_id.has(sync_id):
		var synced = _by_sync_id[sync_id]
		if synced != null and is_instance_valid(synced):
			return synced
		_by_sync_id.erase(sync_id)
	var bodies: Array = _pool.get(scene_path, [])
	for b in bodies:
		if b != null and is_instance_valid(b) and b.get("is_idle") != null and int(b.is_idle) == 1:
			return b
	if bodies.size() >= MAX_PER_SCENE:
		for b in bodies:
			if b != null and is_instance_valid(b):
				_visual_idle(b)
				return b
	var new_b: Node = scene.instantiate()
	if not _pool.has(scene_path):
		_pool[scene_path] = []
	_pool[scene_path].append(new_b)
	return new_b


func _remove_from_gameplay_pools(bullet: Node, scene_path: String) -> void:
	var ids: Array[String] = [_pool_id_for(scene_path)]
	if bullet.get("pool_id") != null:
		ids.append(str(bullet.pool_id))
	for pid in ids:
		if not PoolManager.pool.has(pid):
			continue
		var entry: Dictionary = PoolManager.pool[pid]
		var bodies: Array = entry.get("body", [])
		bodies.erase(bullet)
		var size: int = bodies.size()
		if size <= 0:
			PoolManager.pool.erase(pid)
		else:
			entry["index"] = wrapi(int(entry.get("index", 0)), 0, size)


func _pool_id_for(scene_path: String) -> String:
	if scene_path.contains("normal_bullet"):
		return "normal_bullet"
	if scene_path.contains("shiro_missile"):
		return "shiro_missile"
	if scene_path.contains("mashiro"):
		return "player_sniper_bullet"
	return "player_bullet"


const ENEMY_BULLET_LAYER: int = 128  # project 层 8 = enemy_bullet

# 敌方视觉弹对本地玩家开放伤害：只设 enemy_bullet 层 + monitorable，不检测任何东西。
func _open_player_damage_hole(bullet: Node, damage: int, knockback: int) -> void:
	# 遍历所有 HitBox（不只第一个），保证多判定体弹的"伤害洞"完整
	var boxes: Array = []
	if bullet is HitBox:
		boxes.append(bullet)
	else:
		for n in bullet.find_children("*", "Area2D", true, false):
			if n is HitBox:
				boxes.append(n)
	if boxes.is_empty():
		return
	for hb in boxes:
		var data: DamageData = DamageData.make({
			"damage": maxi(1, damage),
			"type": GameTags.BULLET_DAMAGE,
			"source": DamageRouter.source_tag(Faction.ENEMY_SIDE),
			"knockback": maxi(0, knockback),
			"node": hb,
		})
		hb.set("damage_data", data)
		hb.set("manages_own_hits", false)
		hb.collision_layer = ENEMY_BULLET_LAYER
		hb.collision_mask = 0
		hb.monitoring = false
		hb.monitorable = true
		for shape in hb.find_children("*", "CollisionShape2D", true, false):
			var cs := shape as CollisionShape2D
			if cs != null:
				cs.disabled = false
				cs.set_deferred("disabled", false)


func _disable_damage(bullet: Node) -> void:
	var stack: Array[Node] = [bullet]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject2D:
			n.set_collision_layer(0)
			n.set_collision_mask(0)
			if n is Area2D:
				n.monitoring = false
				n.monitorable = false
				# 注意：不要在这里 set_physics_process(false)。子弹/导弹的移动在自身 _physics_process 里，
				# 关掉会把远端视觉弹冻住。需要停 process 的只有 player/summon 镜像的 HurtBox 轮询
				# （由 coop_player_proxy._disable_areas / coop_summoned_proxy._disable_damage_nodes 处理）。
		elif n is CollisionShape2D:
			n.disabled = true
		for c in n.get_children():
			stack.append(c)
