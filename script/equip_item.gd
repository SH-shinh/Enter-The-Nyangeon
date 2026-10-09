class_name EquipItem
extends Node2D

# 道具通用基类
# 子类只需实现 _apply_effect(quantity)，可选实现 _on_equip / _setup，
# 以及用 attach_rail_icon / attach_follow_icon 挂载图标。

var item_id: String
var num: int = 0

func _ready() -> void:
	item_id = _get_item_id()
	_on_equip()
	_apply_effect(1)
	_setup()
	GameEvents.ability_upgrade_added.connect(_on_upgrade_added)
	PlayerData.update_player_ability()

# 默认按场景文件名推导道具 id（upgrade_manager 以 res://scenes/update_item/<id>.tscn 加载）
# 如需写死可覆盖此函数返回字符串。
func _get_item_id() -> String:
	var path := get_scene_file_path()
	if path != "":
		return path.get_file().get_basename()
	return name

func _on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary) -> void:
	if upgrade.id != item_id:
		return
	if current_upgrade[item_id]["quantity"] == 1:
		return
	num = current_upgrade[item_id]["quantity"]
	_apply_effect(num)
	PlayerData.update_player_ability()

# 首次获取时的一次性初始化：生成 body、挂载图标、连接额外信号等
func _on_equip() -> void:
	pass

# 额外的信号连接钩子（在 _on_equip 与首次 _apply_effect 之后调用）
func _setup() -> void:
	pass

# 属性/效果应用：首次以 quantity = 1 调用，之后每次叠加以当前数量调用
func _apply_effect(_quantity: int) -> void:
	pass

# 挂载图标到枪械导轨（占用第一个空闲 Rail）
func attach_rail_icon(icon_scene: PackedScene) -> bool:
	for rail in get_tree().get_nodes_in_group("Rail"):
		if rail.get("picatinny_rail_use") == false:
			var icon := icon_scene.instantiate()
			rail.add_child(icon)
			rail.set("picatinny_rail_use", true)
			return true
	return false

# 挂载图标到头部挂点（占用第一个空闲 Hat）
func attach_hat_icon(icon_scene: PackedScene) -> bool:
	for hat in get_tree().get_nodes_in_group("Hat"):
		if hat.get("hat_use") == false:
			var icon := icon_scene.instantiate()
			hat.add_child(icon)
			hat.set("hat_use", true)
			return true
	return false

# 挂载图标到跟随点（占用第一个空闲 Follow）
func attach_follow_icon(icon_scene: PackedScene) -> bool:
	for follow in get_tree().get_nodes_in_group("Follow"):
		if follow.get("follow_use") == false:
			var icon := icon_scene.instantiate()
			get_tree().get_first_node_in_group("PlayerRoot").add_child(icon)
			icon.call("get_follow", follow)
			follow.set("follow_use", true)
			return true
	return false
