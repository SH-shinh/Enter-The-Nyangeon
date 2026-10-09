extends "res://ui/society_card.gd"

# mod 自带社团卡基类：必须继承本类。
# 场景内设 `group_id`（带 <modid>_ 前缀）与 `members`（本社团角色 id）。
# 覆写动画方法避免依赖 AnimationPlayer 动画资源（但场景仍需含 AnimationPlayer 节点，父类 @onready 会取它）。

const MOD_CARD := preload("res://ui/mod_player_card.tscn")

@export var members: Array[String] = []


func mouse_select_anim() -> void:
	pass


func mouse_out_anim() -> void:
	pass


func on_select_handle() -> void:
	if on_select:
		return
	on_select = true
	GameEvents.emit_society_card_selected(self)
	close_card()


func out_select_card() -> void:
	on_select = false
	open_card()


# 社团可见性：任一成员已解锁（auto 或已购买）即显示；替代父类的 PlayerData.group 门。
func check_group() -> void:
	var any_visible := false
	for id in members:
		if not ModManager.is_character_locked(id):
			any_visible = true
			break
	self.visible = any_visible


func populate_player_cards(box: Node) -> void:
	for id in members:
		if ModManager.is_character_locked(id):
			continue
		var card = ModManager.get_resource("characters", id)
		if card == null:
			continue
		var scene := ModManager.get_card_scene(id)
		var ins: Node
		if scene != null:
			ins = scene.instantiate()
		else:
			ins = MOD_CARD.instantiate()
		ins.player_card = card
		box.add_child(ins)
		if ins.has_method("set_branches"):
			ins.call("set_branches", card)
		await get_tree().create_timer(0.07).timeout
