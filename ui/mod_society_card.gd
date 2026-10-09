extends "res://ui/society_card.gd"

# 动态「MOD」社团卡：存在 mod 角色时可见；点击后把 mod 角色卡填入 PlayerCardBox。
# 覆写 society_card 的动画相关方法，避免依赖 AnimationPlayer 动画资源。

const MOD_CARD := preload("res://ui/mod_player_card.tscn")


func check_group() -> void:
	self.visible = not ModManager.get_unclaimed_unlocked_characters().is_empty()


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


func populate_player_cards(box: Node) -> void:
	for card in ModManager.get_unclaimed_unlocked_characters():
		var scene := ModManager.get_card_scene(card.id)
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
