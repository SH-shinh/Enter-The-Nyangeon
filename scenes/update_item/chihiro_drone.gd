extends EquipItem
## Chihiro 专属无人机控制器（装备）：装备时生成/管理环绕无人机。
## 无人机挂 EquipLayer（世界层）跟随玩家，不随装备销毁，需显式清理；
## 测试房 reset_clear_unit() 会清空 EquipLayer，故这里靠 _process 轮询自愈补台。
## 台数按 PS 等级 T0 1 / T1 2 / T2 2 / T3 3。

const DRONE_SCENE := preload("res://scenes/player/chihiro/chihiro_drone_body.tscn")
const DRONE_COUNT: Array[int] = [1, 2, 2, 3]

var _drones: Array[Node] = []
var _tier: int = -1
var _sync_accum: float = 0.0


func _on_equip() -> void:
	_sync()


func _apply_effect(_quantity: int) -> void:
	_sync()


func set_tier(_t: int) -> void:
	_sync()


func _exit_tree() -> void:
	for d in _drones:
		if is_instance_valid(d):
			d.queue_free()
	_drones.clear()


func _process(delta: float) -> void:
	_sync_accum += delta
	if _sync_accum < 0.2:
		return
	_sync_accum = 0.0
	var tier_changed := _ps_tier() != _tier
	if tier_changed or _needs_sync():
		_sync()


func _needs_sync() -> bool:
	var want: int = DRONE_COUNT[clampi(_tier, 0, 3)] if _tier >= 0 else DRONE_COUNT[0]
	var valid := 0
	for d in _drones:
		if is_instance_valid(d):
			valid += 1
	return valid != want


func _ps_tier() -> int:
	var p := player
	if p == null or not is_instance_valid(p):
		return 0
	var ps = p.get_node_or_null("ChihiroPS")
	if ps == null:
		return 0
	return clampi(int(ps.get("now_t")), 0, 3)


# 和 Shiroko 无人机一致挂 EquipLayer；测试/独立场景回退 PlayerRoot / 玩家父节点。
func _host_layer() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var layer := tree.get_first_node_in_group("EquipLayer")
	if layer != null:
		return layer
	layer = tree.get_first_node_in_group("PlayerRoot")
	if layer != null:
		return layer
	var p := player
	if p != null and is_instance_valid(p):
		return p.get_parent()
	return null


func _sync() -> void:
	_tier = _ps_tier()
	var want: int = DRONE_COUNT[_tier]
	var host := _host_layer()
	if host == null:
		return
	for i in range(_drones.size() - 1, -1, -1):
		if not is_instance_valid(_drones[i]):
			_drones.remove_at(i)
	while _drones.size() < want:
		var index := _drones.size()
		var d = DRONE_SCENE.instantiate()
		d.name = "ChihiroDroneBody%d" % index
		d.set("player", player)
		d.set("tier", _tier)
		d.set("phase", TAU * float(index) / float(want))
		host.add_child(d)
		_drones.append(d)
	while _drones.size() > want:
		var d = _drones.pop_back()
		if is_instance_valid(d):
			d.queue_free()
	for i in _drones.size():
		var d = _drones[i]
		if not is_instance_valid(d):
			continue
		if d.has_method("set_orbit"):
			d.call("set_orbit", i, _drones.size())
		if d.has_method("set_tier"):
			d.call("set_tier", _tier)
