class_name BuffRouter

## target 的 buff 管理器缓存键：命中后跳过每次 3×`get` + 3×`find_child` 递归。
## 用 manager.body == target 校验，池化/重建后旧缓存自动失效。
const MGR_CACHE_META := &"_buff_router_mgr"

static func apply_buff(target: Node, buff: Buff, value: Array, source_id: String = ""):
	# mod 扩展点：光环等命中"远端玩家镜像"时由 mod 转交归属端（未注入即原行为）
	if ExtensionHooks.intercept_named("player_buff_apply_interceptor", [target, buff, value]):
		return
	var manager: Node = resolve_manager(target)
	if manager != null and manager.has_method("apply_buff"):
		manager.apply_buff(buff, value, source_id)

static func remove_buff(target: Node, buff: Buff):
	if ExtensionHooks.intercept_named("player_buff_remove_interceptor", [target, buff]):
		return
	var manager: Node = resolve_manager(target)
	if manager != null and manager.has_method("remove_buff"):
		manager.remove_buff(buff)

static func remove_source(target: Node, buff: Buff, source_id: String):
	if ExtensionHooks.intercept_named("player_buff_remove_interceptor", [target, buff]):
		return
	var manager: Node = resolve_manager(target)
	if manager != null and manager.has_method("remove_source"):
		manager.remove_source(buff, source_id)

static func refresh_buff(target: Node, id: String):
	var manager: Node = resolve_manager(target)
	if manager != null and manager.has_method("refresh_buff"):
		manager.refresh_buff(id)

static func resolve_manager(target: Node) -> Node:
	if target == null or not is_instance_valid(target):
		return null
	if target.has_meta(MGR_CACHE_META):
		var cached = target.get_meta(MGR_CACHE_META)
		if cached != null and is_instance_valid(cached) and cached.get("body") == target:
			return cached
	for key in ["player_buff_manager", "summoned_buff_manager", "enemy_buff_manager"]:
		var manager = target.get(key)
		if manager != null:
			target.set_meta(MGR_CACHE_META, manager)
			return manager
	for node_name in ["PlayerBuffManager", "SummonedBuffManager", "EnemyBuffManager"]:
		var manager = target.find_child(node_name, true, false)
		if manager != null:
			target.set_meta(MGR_CACHE_META, manager)
			return manager
	return null

static func is_ally(target: Node) -> bool:
	return Faction.of_entity(target) == Faction.PLAYER_SIDE
