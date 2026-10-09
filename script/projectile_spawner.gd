class_name ProjectileSpawner

## 弹道生成收敛器：统一「取池/新建 → 配置 → 入树 → 激活 → 通知」。
## 本体所有 BulletRoot 生成点统一走 spawn_core（位置参数，避免高频 Dictionary 分配）。
## 联机 mod 通过 ExtensionHooks.on_projectile_spawned 接收生成通知。
##
## 顺序语义严格对齐原生成点：
##   add_before_activate=true  → 先入树、再 pre_activate、再激活（player_gun）
##   add_before_activate=false → 先激活、再入树（bullet_launcher 等）
##   deferred_add=true         → 激活后延迟入树，post 亦延迟（bullet_launcher_2 分支2）
##
## scale 传 Vector2.ZERO 表示「不改写缩放」（如 player_gun 由伤害信号回填）。
##
## 注意：configure 在入树前执行，**不得**访问新节点的 @onready / _enter_tree 子节点
## （如 bullet.hit_box）；这类「入树后才可用」的初始化请放 pre_activate（入树之后、activate 之前）。

static func acquire(pool_id: String, scene: PackedScene) -> Dictionary:
	var node: Node = null
	if pool_id != "":
		node = PoolManager.get_pool(pool_id)
	if node == null or node.is_idle == 0:
		if scene == null:
			return {"node": null, "is_new": false}
		node = scene.instantiate()
		return {"node": node, "is_new": true}
	return {"node": node, "is_new": false}


static func spawn_core(
	scene: PackedScene,
	pool_id: String,
	root_group: String,
	owner: Node,
	source_faction: int,
	position: Vector2,
	rotation: float,
	scale: Vector2,
	add_before_activate: bool,
	deferred_add: bool,
	notify: bool,
	configure: Callable = Callable(),
	pre_activate: Callable = Callable(),
	post: Callable = Callable()
) -> Node:
	var acquired := acquire(pool_id, scene)
	var node: Node = acquired["node"]
	if node == null:
		return null
	var is_new: bool = acquired["is_new"]

	if configure.is_valid():
		configure.call(node)

	node.global_position = position
	node.global_rotation = rotation
	if scale != Vector2.ZERO:
		node.scale = scale

	var root := _root_node(root_group)

	if add_before_activate:
		if is_new and root != null:
			root.add_child(node)
		if pre_activate.is_valid():
			pre_activate.call(node)
		_activate(node)
		if post.is_valid():
			post.call(node)
	else:
		_activate(node)
		if is_new and root != null:
			if deferred_add:
				root.call_deferred("add_child", node)
				if post.is_valid():
					post.call_deferred(node)
			else:
				root.add_child(node)
				if post.is_valid():
					post.call(node)
		elif post.is_valid():
			post.call(node)

	if notify and ExtensionHooks.on_projectile_spawned.is_valid():
		ExtensionHooks.on_projectile_spawned.call(node, owner, source_faction)
	return node


# mod 生成远程视觉副本时标记，避免回环广播 / 被 on_projectile_despawned 误判为本地产物。
static func mark_remote(node: Node) -> void:
	if node != null:
		node.set_meta("remote_visual", true)


# 特例站点（取池/新建逻辑无法走 spawn_core，如 self.duplicate()）手动触发本地生成通知。
static func notify_local(node: Node, owner: Node, source_faction: int) -> void:
	if node != null and ExtensionHooks.on_projectile_spawned.is_valid():
		ExtensionHooks.on_projectile_spawned.call(node, owner, source_faction)


static func _activate(node: Node) -> void:
	if node.has_method("active_state"):
		node.active_state()


static func _root_node(root_group: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).get_first_node_in_group(root_group)
	return null
