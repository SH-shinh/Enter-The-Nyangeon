class_name BuffManagerBase
extends Node

signal buff_applied(buff: Buff, current_buff: Dictionary)
signal buff_layer_changed(buff: Buff, entry: Dictionary)
signal buff_consumed(buff: Buff)
signal buff_expired(buff: Buff)
@warning_ignore("unused_signal")
signal buff_success(buff: Buff)

const TICKS_PER_SECOND := 10

@export var buff_card: PackedScene

var current_buff: Dictionary = {}
var body: Node
var host: Node

var _components: Dictionary = {}
var _event_subs: Dictionary = {}
var _refresh_dirty: bool = false

func _ready():
	body = get_parent()
	host = _resolve_host()
	set_process(false)
	GameEvents.global_time_count.connect(buff_count)
	_post_ready()

# 释放时断掉 _ensure_event 连到全局/实体信号的事件 lambda，避免 manager 释放后事件触发报
# "Lambda capture was freed"（连接源仍是长生命周期的 GameEvents/stats 等）
func _exit_tree():
	for evt in _event_subs.keys():
		var e = _event_subs[evt]
		if e is Dictionary:
			var s = e.get("sig")
			var cb = e.get("cb")
			if s is Signal and cb is Callable and (s as Signal).is_connected(cb):
				(s as Signal).disconnect(cb)
	_event_subs.clear()

func _resolve_host() -> Node:
	return body.get("stats")

func _host_kind() -> int:
	return BuffStatMap.ENEMY

func _post_ready() -> void:
	pass

func _can_apply() -> bool:
	return true

func _can_tick() -> bool:
	return true

func _layer_mult() -> float:
	return 1.0

func _buff_box() -> Node:
	return body.get("buff_box")

func _host_refresh() -> void:
	if host == null or not host.has_method("update_body_ability"):
		return
	_refresh_dirty = true
	set_process(true)

func _process(_delta: float) -> void:
	if _refresh_dirty:
		_refresh_dirty = false
		host.update_body_ability()
	if not _refresh_dirty:
		set_process(false)

func _audience_ok(buff: Buff) -> bool:
	if buff.audience == Faction.ANY:
		return true
	return buff.audience == Faction.of_entity(body)

func apply_buff(buff: Buff, value: Array, source_id: String = "", applier_stats: Dictionary = {}, applier_peer: int = 0):
	if ExtensionHooks.intercept(ExtensionHooks.enemy_buff_apply_gate, [self, buff, value, source_id]):
		return
	if not _can_apply():
		return
	if buff.id == "":
		return
	if not _audience_ok(buff):
		return
	var entry: Dictionary
	if current_buff.has(buff.id):
		entry = current_buff[buff.id]
		if not applier_stats.is_empty():
			entry["applier_stats"] = applier_stats
		if applier_peer != 0:
			entry["applier_peer"] = applier_peer
		if entry["stop"]:
			return
		entry["now_time"] = 0
		# 来源引用计数：多来源只维持"存在"，不叠层/不重复加值；记录来源用于独立移除
		if buff.source_refcount:
			entry["sources"][source_id if source_id != "" else "_local"] = true
			_sync_card_layer(entry)
			_update_card(entry)
			buff_layer_changed.emit(buff, entry)
			return
		if _uses_source_caps(buff):
			if not _add_source_layer(entry, source_id, value):
				return
		else:
			if entry["layer"] >= entry["max_layer"]:
				return
			entry["layer"] += 1
		_sync_card_layer(entry)
		_refresh_component(entry)
		buff_layer_changed.emit(buff, entry)
	else:
		entry = _create_entry(buff, value)
		entry["applier_stats"] = applier_stats
		entry["applier_peer"] = applier_peer
		if buff.source_refcount:
			entry["sources"][source_id if source_id != "" else "_local"] = true
			_sync_card_layer(entry)
		elif _uses_source_caps(buff):
			entry["layer"] = 0
			_add_source_layer(entry, source_id, value)
			_sync_card_layer(entry)
		current_buff[buff.id] = entry
		_ensure_event(buff.consume_event)
		_activate_component(entry)
	_on_buff_applied(entry)
	_apply_ability(entry, 1)
	buff_applied.emit(buff, current_buff)
	# 联机：host 侧把 host 发起的敌人 buff 广播（客户机镜像应用）
	ExtensionHooks.notify(ExtensionHooks.on_enemy_buff_applied, [self, buff, value, source_id, applier_stats, applier_peer])

# ---------------- 来源独立上限 ----------------
# 覆写返回 true 后，层数按来源（道具）分别累计：每个来源各自有上限，
# 互不侵占，总层数为各来源层数之和。value[0] 为该来源的上限。
# 默认读 Buff.per_source_layers 字段（如 utaha_buff）。
func _uses_source_caps(buff: Buff) -> bool:
	return buff != null and buff.per_source_layers

func _add_source_layer(entry: Dictionary, source_id: String, value: Array) -> bool:
	var cap: int = max(1, int(value[0]))
	if source_id == "":
		source_id = "_default"
	var layers: Dictionary = entry["source_layers"]
	var caps: Dictionary = entry["source_caps"]
	caps[source_id] = cap
	var current: int = int(layers.get(source_id, 0))
	if current >= cap:
		return false
	layers[source_id] = current + 1
	entry["source_layers"] = layers
	entry["source_caps"] = caps
	entry["layer"] += 1
	entry["max_layer"] = _source_cap_total(entry)
	return true

func _source_cap_total(entry: Dictionary) -> int:
	var total := 0
	for key in entry["source_caps"]:
		total += int(entry["source_caps"][key])
	return total

# 来源模式下的掉层：从当前层数最多的来源扣 1 层
func _decay_source_layer(entry: Dictionary) -> void:
	var layers: Dictionary = entry["source_layers"]
	var target := ""
	var most := 0
	for key in layers:
		var count: int = int(layers[key])
		if count > most:
			most = count
			target = key
	if target == "":
		return
	layers[target] = int(layers[target]) - 1
	entry["source_layers"] = layers
	entry["layer"] = max(0, entry["layer"] - 1)

func remove_buff(buff: Buff):
	if current_buff.has(buff.id):
		_remove_buff_entry(buff.id)

# 按来源移除：source_refcount 清该来源 1 层；per_source_layers 移除该来源全部层数。
func remove_source(buff: Buff, source_id: String):
	if not current_buff.has(buff.id):
		return
	if _uses_source_caps(buff):
		var ce: Dictionary = current_buff[buff.id]
		var csrc: String = source_id if source_id != "" else "_default"
		var n: int = int(ce["source_layers"].get(csrc, 0))
		if n <= 0:
			return
		ce["source_layers"].erase(csrc)
		ce["source_caps"].erase(csrc)
		ce["layer"] = max(0, ce["layer"] - n)
		ce["max_layer"] = _source_cap_total(ce)
		_remove_ability(ce, n)
		if ce["layer"] <= 0:
			_remove_buff_entry(buff.id)
		else:
			ce["now_time"] = 0
			_sync_card_layer(ce)
			_update_card(ce)
			buff_layer_changed.emit(buff, ce)
		return
	if not buff.source_refcount:
		remove_buff(buff)
		return
	var entry: Dictionary = current_buff[buff.id]
	var src: String = source_id if source_id != "" else "_local"
	if not entry["sources"].has(src):
		return
	entry["sources"].erase(src)
	if entry["sources"].is_empty():
		_remove_buff_entry(buff.id)
	else:
		entry["now_time"] = 0
		_sync_card_layer(entry)
		_update_card(entry)
		buff_layer_changed.emit(buff, entry)

# 清掉某来源在所有按来源计数的 buff 上的引用（联机 owner 断线兜底）
func remove_source_all(source_id: String):
	var src: String = source_id if source_id != "" else "_local"
	var src_caps: String = source_id if source_id != "" else "_default"
	for id in current_buff.keys():
		if not current_buff.has(id):
			continue
		var entry: Dictionary = current_buff[id]
		var res: Buff = entry["resource"]
		if _uses_source_caps(res):
			if entry["source_layers"].has(src_caps):
				remove_source(res, source_id)
		elif res.source_refcount and entry["sources"].has(src):
			remove_source(res, source_id)

func clear_all_buff():
	if not current_buff.is_empty():
		for id in current_buff.keys():
			_remove_buff_entry(id)
	release_idle_cards()

func release_idle_cards():
	var box: Node = _buff_box()
	if box == null:
		return
	for child in box.get_children():
		if child.get("is_idle") == 1 and child.has_method("release_to_pool"):
			child.release_to_pool()

func clear_by_audience(side: int):
	var ids: Array = current_buff.keys()
	for id in ids:
		if not current_buff.has(id):
			continue
		var entry: Dictionary = current_buff[id]
		if entry["resource"].audience == side:
			_remove_buff_entry(id)

func on_faction_changed():
	clear_all_buff()

func consume_buff(id: String, layers: int = 1):
	if not current_buff.has(id):
		return
	var resource: Buff = current_buff[id]["resource"]
	if resource.remove_by_layer:
		for i in layers:
			if not current_buff.has(id):
				break
			_expire_buff(id)
	else:
		_remove_buff_entry(id)
	buff_consumed.emit(resource)

func refresh_buff(id: String):
	if not current_buff.has(id):
		return
	var entry: Dictionary = current_buff[id]
	if entry["stop"]:
		return
	entry["now_time"] = 0
	_update_card(entry)

func buff_count():
	if current_buff.is_empty():
		return
	if not _can_tick():
		return
	for id in current_buff.keys():
		if not current_buff.has(id):
			continue
		var entry: Dictionary = current_buff[id]
		if entry["stop"]:
			continue
		entry["now_time"] += 1
		_update_card(entry)
		_tick_entry(entry)
		if current_buff.has(id) and entry["now_time"] > entry["erase_time"]:
			_expire_buff(id)

func _create_entry(buff: Buff, value: Array) -> Dictionary:
	var entry: Dictionary = {
		"resource": buff,
		"layer": 1,
		"max_layer": _scale_max_layer(value[0]),
		"value": value[1],
		"raw_value": value.duplicate(),
		"erase_time": value[2] * TICKS_PER_SECOND * _duration_multiplier(buff),
		"now_time": 0,
		"dot_time": 0,
		"now_dot_time": 0,
		"source_layers": {},
		"source_caps": {},
		"sources": {},
		"buff_card": _obtain_buff_card(buff),
		"stop": false,
		"applier_stats": {},
		"applier_peer": 0,
	}
	_configure_entry(entry)
	_update_card(entry)
	_sync_card_layer(entry)
	return entry

func _scale_max_layer(base: int) -> int:
	return base

# buff 时长乘区：默认 1；子类可覆写（玩家侧只对有益 buff 生效）
func _duration_multiplier(_buff: Buff) -> float:
	return 1.0

func _configure_entry(_entry: Dictionary) -> void:
	pass

func _on_buff_applied(_entry: Dictionary) -> void:
	pass

func _tick_entry(_entry: Dictionary) -> void:
	pass

func _on_layer_changed(_entry: Dictionary) -> void:
	pass

func _on_entry_removed(_id: String) -> void:
	pass

func _apply_ability(entry: Dictionary, layers: int):
	var resource: Buff = entry["resource"]
	var changed := false
	if resource.ability != "":
		host.set(resource.ability, host.get(resource.ability) + entry["value"] * layers)
		changed = true
	if _apply_extra_ability(entry, layers):
		changed = true
	if _apply_modifiers(entry, layers, true):
		changed = true
	if changed:
		_host_refresh()

func _remove_ability(entry: Dictionary, layers: int):
	var resource: Buff = entry["resource"]
	var changed := false
	if resource.ability != "":
		host.set(resource.ability, host.get(resource.ability) - entry["value"] * layers)
		changed = true
	if _remove_extra_ability(entry, layers):
		changed = true
	if _apply_modifiers(entry, layers, false):
		changed = true
	if changed:
		_host_refresh()

func _apply_extra_ability(_entry: Dictionary, _layers: int) -> bool:
	return false

func _remove_extra_ability(_entry: Dictionary, _layers: int) -> bool:
	return false

func _apply_modifiers(entry: Dictionary, layers: int, add: bool) -> bool:
	var resource: Buff = entry["resource"]
	if resource.modifiers.is_empty():
		return false
	var changed := false
	for modifier in resource.modifiers:
		var key: String = modifier.get("key", "")
		if key == "":
			continue
		var field: String = BuffStatMap.resolve(_host_kind(), key)
		if field == "" or host.get(field) == null:
			continue
		var if_value = modifier.get("if_value", null)
		if if_value != null and not is_equal_approx(float(entry["value"]), float(if_value)):
			continue
		var if_gt = modifier.get("if_gt", null)
		if if_gt != null and float(entry["value"]) <= float(if_gt):
			continue
		var mode: String = modifier.get("mode", "add")
		var source: String = modifier.get("source", "value")
		var delta: float = float(entry["value"]) if source == "value" else float(modifier.get("amount", 0.0))
		delta *= layers
		var current = host.get(field)
		if mode == "mult":
			var factor: float = delta if add else (1.0 / delta if delta != 0.0 else 1.0)
			host.set(field, current * factor)
		else:
			host.set(field, current + (delta if add else -delta))
		changed = true
	return changed

func _expire_buff(id: String):
	if not current_buff.has(id):
		return
	var entry: Dictionary = current_buff[id]
	if entry["stop"]:
		return
	entry["now_time"] = 0
	if not entry["resource"].remove_by_layer:
		_notify_component_timeout(entry)
		_remove_buff_entry(id)
		return
	if _uses_source_caps(entry["resource"]):
		_decay_source_layer(entry)
	else:
		entry["layer"] -= 1
	_sync_card_layer(entry)
	_remove_ability(entry, 1)
	if entry["layer"] > 0:
		_on_layer_changed(entry)
		return
	_notify_component_timeout(entry)
	_remove_buff_entry(id)

func _remove_buff_entry(id: String):
	if not current_buff.has(id):
		return
	var entry: Dictionary = current_buff[id]
	if entry["stop"]:
		return
	entry["stop"] = true
	_remove_ability(entry, entry["layer"])
	_deactivate_component(entry)
	_clear_card(entry)
	_on_entry_removed(id)
	ExtensionHooks.notify(ExtensionHooks.on_enemy_buff_removed, [body, id])
	current_buff.erase(id)
	buff_expired.emit(entry["resource"])

func _obtain_buff_card(buff: Buff):
	var box: Node = _buff_box()
	if box == null:
		return null
	var card = _find_idle_card(box)
	if card == null:
		card = PoolManager.get_buff_pool()
		if card != null:
			card.reparent(box)
		else:
			card = buff_card.instantiate()
			box.add_child(card)
	card.set_buff_card(buff)
	card.active_state()
	return card

func _find_idle_card(box: Node):
	for child in box.get_children():
		if child.get("is_idle") == 1:
			return child
	return null

func _update_card(entry: Dictionary):
	if entry["buff_card"] != null:
		entry["buff_card"].now_time = entry["now_time"]
		entry["buff_card"].erase_time = entry["erase_time"]

func _sync_card_layer(entry: Dictionary):
	if entry["buff_card"] == null:
		return
	# source_refcount：卡片显示"当前来源数"（仅展示；效果仍只算 1 层）
	if entry["resource"] != null and entry["resource"].source_refcount:
		entry["buff_card"].layer = max(1, entry["sources"].size())
	else:
		entry["buff_card"].layer = entry["layer"]

func _clear_card(entry: Dictionary):
	if entry["buff_card"] != null:
		entry["buff_card"].clear_card()

func _activate_component(entry: Dictionary):
	var resource: Buff = entry["resource"]
	if resource.component_scene == null:
		return
	var comp = _components.get(resource.id)
	if comp == null:
		comp = resource.component_scene.instantiate()
		add_child(comp)
		_components[resource.id] = comp
		if comp.has_method("setup"):
			comp.setup(self, body)
	if comp.has_method("activate"):
		comp.activate(entry)

func _refresh_component(entry: Dictionary):
	var comp = _components.get(entry["resource"].id)
	if comp != null and comp.has_method("refresh"):
		comp.refresh(entry)

func _deactivate_component(entry: Dictionary):
	var comp = _components.get(entry["resource"].id)
	if comp != null and comp.has_method("deactivate"):
		comp.deactivate()

func _notify_component_timeout(entry: Dictionary):
	var comp = _components.get(entry["resource"].id)
	if comp != null and comp.has_method("on_timeout"):
		comp.on_timeout(entry)

func _ensure_event(evt: String):
	if evt == "" or _event_subs.has(evt):
		return
	var sources: Array = [GameEvents, host, body]
	if body != null:
		var stats = body.get("stats")
		if stats != null:
			sources.append(stats)
	for src in sources:
		if src == null:
			continue
		var sig = src.get(evt)
		if sig is Signal:
			var cb: Callable = func(_a=null, _b=null, _c=null, _d=null, _e=null): _consume_by_event(evt)
			(sig as Signal).connect(cb)
			_event_subs[evt] = {"sig": sig, "cb": cb}
			return

func _consume_by_event(evt: String):
	for id in current_buff.keys():
		if not current_buff.has(id):
			continue
		if current_buff[id]["resource"].consume_event == evt:
			consume_buff(id, 1)
