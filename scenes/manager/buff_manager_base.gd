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

func apply_buff(buff: Buff, value: Array):
	if not _can_apply():
		return
	if buff.id == "":
		return
	if not _audience_ok(buff):
		return
	var entry: Dictionary
	if current_buff.has(buff.id):
		entry = current_buff[buff.id]
		if entry["stop"]:
			return
		entry["now_time"] = 0
		if entry["layer"] >= entry["max_layer"]:
			return
		entry["layer"] += 1
		_sync_card_layer(entry)
		_refresh_component(entry)
		buff_layer_changed.emit(buff, entry)
	else:
		entry = _create_entry(buff, value)
		current_buff[buff.id] = entry
		_ensure_event(buff.consume_event)
		_activate_component(entry)
	_on_buff_applied(entry)
	_apply_ability(entry, 1)
	buff_applied.emit(buff, current_buff)

func remove_buff(buff: Buff):
	if current_buff.has(buff.id):
		_remove_buff_entry(buff.id)

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
		var entry: Dictionary = current_buff[id]
		if entry["stop"]:
			continue
		entry["now_time"] += 1
		_update_card(entry)
		_tick_entry(entry)
		if entry["now_time"] > entry["erase_time"]:
			_expire_buff(id)

func _create_entry(buff: Buff, value: Array) -> Dictionary:
	var entry: Dictionary = {
		"resource": buff,
		"layer": 1,
		"max_layer": _scale_max_layer(value[0]),
		"value": value[1],
		"erase_time": value[2] * TICKS_PER_SECOND,
		"now_time": 0,
		"dot_time": 0,
		"now_dot_time": 0,
		"buff_card": _obtain_buff_card(buff),
		"stop": false,
	}
	_configure_entry(entry)
	_update_card(entry)
	_sync_card_layer(entry)
	return entry

func _scale_max_layer(base: int) -> int:
	return base

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
	var entry: Dictionary = current_buff[id]
	if entry["stop"]:
		return
	entry["now_time"] = 0
	if not entry["resource"].remove_by_layer:
		_notify_component_timeout(entry)
		_remove_buff_entry(id)
		return
	entry["layer"] -= 1
	_sync_card_layer(entry)
	_remove_ability(entry, 1)
	if entry["layer"] > 0:
		_on_layer_changed(entry)
		return
	_notify_component_timeout(entry)
	_remove_buff_entry(id)

func _remove_buff_entry(id: String):
	var entry: Dictionary = current_buff[id]
	if entry["stop"]:
		return
	entry["stop"] = true
	_remove_ability(entry, entry["layer"])
	_deactivate_component(entry)
	_clear_card(entry)
	_on_entry_removed(id)
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
	if entry["buff_card"] != null:
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
			_event_subs[evt] = true
			sig.connect(func(_a=null, _b=null, _c=null, _d=null, _e=null): _consume_by_event(evt))
			return

func _consume_by_event(evt: String):
	for id in current_buff.keys():
		if not current_buff.has(id):
			continue
		if current_buff[id]["resource"].consume_event == evt:
			consume_buff(id, 1)
