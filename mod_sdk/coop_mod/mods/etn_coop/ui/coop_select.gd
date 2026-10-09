extends CanvasLayer

## 联机选人覆盖层：布局仿主菜单 SelectPlayer（左角色卡 + 右社团卡），
## 顶部一行「支援角色选择」（复用支援商店卡，首项为「空」支援位）。
## 点击角色卡 = 确认该角色（发 character_confirmed，由 CoopFlow 上报并转已就绪）。
## 世界在选人期间被全局暂停，故场景根 process_mode=ALWAYS 以保持可交互。
## 静态布局在 coop_select.tscn 里，可在编辑器手动调整；本脚本负责动态数据填充。

signal character_confirmed(scene_path: String)

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const MOD_SOCIETY_SCENE := preload("res://ui/mod_society_card.tscn")
const MOD_PAGE_SIZE := 4
const SUPPORT_CARD_SCENE := preload("res://ui/support_ui/support_shop_card.tscn")

@onready var _player_box: HBoxContainer = %PlayerBox
@onready var _society_box: VBoxContainer = %SocietyBox
@onready var _support_box: HBoxContainer = %SupportBox
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _active_society: Node = null
var _confirming: bool = false
var _interactive: bool = true


func _ready() -> void:
	GameEvents.society_card_selected.connect(_on_society_selected)
	GameEvents.player_card_id.connect(_on_player_card_id)
	GameEvents.support_card_select.connect(_on_support_card_select)
	# 默认不带支援（首项「空」）
	if SupportData.null_support != null:
		SupportData.game_support = SupportData.null_support
	_report_local_support()
	_build_supports()
	_build_societies()
	call_deferred("_select_first_society")
	if _anim != null and _anim.has_animation("show_anim"):
		_anim.play("show_anim")


# 关闭时倒放进场动画（由 CoopFlow 调用，随后延时释放本层）
func play_hide() -> void:
	if _anim != null and _anim.has_animation("show_anim"):
		_anim.play_backwards("show_anim")


# 确认角色后本层被“已就绪/难度”遮盖。只切输入可交互性，**不改 process_mode**：
# 设成 DISABLED 会把角色卡的 select_anim（AnimationPlayer）一并冻结，导致动画要等
# 取消就绪才补播。就绪/难度取消时再恢复输入。
func set_interactive(v: bool) -> void:
	_interactive = v
	# 重新启用（取消就绪/取消难度）时复位确认标志，否则 _on_player_card_id 会一直早退，
	# 导致取消后无法再次选人（本层实例不会重建）。
	if v:
		_confirming = false
	_set_cards_interactive(v)


# 切换 %PlayerBox 内角色卡的输入：
# - 官方卡（player_card.gd）：mouse_open/mouse_close 切 mouse_filter，并复位 on_select/on_touch。
#   官方卡的选择会经 player_card_selected → mouse_close 永久置 IGNORE，而恢复用的 mouse_open
#   只在 level_select_out 触发；coop 从不发该信号，故取消就绪时须手动恢复（否则当前社团
#   的卡不可再选，只有切换社团重新实例化的卡能选）。
# - mod 卡（mod_player_card.gd，Button）：无 mouse_open，退化为 disabled。
func _set_cards_interactive(enabled: bool) -> void:
	for card in _player_box.get_children():
		if card.has_method("mouse_open") and card.has_method("mouse_close"):
			card.call("mouse_open" if enabled else "mouse_close")
		elif card is BaseButton:
			card.disabled = not enabled


func _build_supports() -> void:
	if SupportData.null_support != null:
		_add_support_card(SupportData.null_support)
	# 只显示已解锁支援（与本体关卡选择的支援选择一致）
	if SupportData.support_data == null:
		return
	for entry in SupportData.support_data.values():
		var card = entry.get("resource") if entry is Dictionary else null
		if card != null and card != SupportData.null_support:
			_add_support_card(card)


func _add_support_card(card: SupportCard) -> void:
	var ins = SUPPORT_CARD_SCENE.instantiate()
	ins.shop_card = card
	_support_box.add_child(ins)
	if card.character_sprite_path != "" and ins.has_method("reveal"):
		ins.call("reveal")


func _build_societies() -> void:
	# 只实例化已解锁社团（本体注册表 + mod 社团 + MOD 通用卡）
	for s in ModManager.get_base_societies():
		if not PlayerData.group.has(str(s.get("group_id", ""))):
			continue
		var base_scene = s.get("scene")
		if base_scene != null:
			_society_box.add_child(base_scene.instantiate())
	for s in ModManager.get_mod_societies():
		if not PlayerData.group.has(str(s.get("group_id", ""))):
			continue
		var scene = s.get("scene")
		if scene != null:
			_society_box.add_child(scene.instantiate())
	if not ModManager.get_unclaimed_unlocked_characters().is_empty():
		# 通用「MOD」社团卡：每 MOD_PAGE_SIZE 个未认领角色一张，>4 时自动续卡（MOD / MOD 2 / …）。
		var mod_ids: Array[String] = []
		for card in ModManager.get_unclaimed_unlocked_characters():
			if card != null:
				mod_ids.append(str(card.id))
		var mod_pages := int(ceil(float(mod_ids.size()) / MOD_PAGE_SIZE))
		for p in mod_pages:
			var ins = MOD_SOCIETY_SCENE.instantiate()
			var slice: Array[String] = []
			for i in range(MOD_PAGE_SIZE):
				var idx := p * MOD_PAGE_SIZE + i
				if idx < mod_ids.size():
					slice.append(mod_ids[idx])
			ins.set("members", slice)
			if ins.has_method("set_page"):
				ins.call("set_page", p, mod_pages)
			_society_box.add_child(ins)


func _select_first_society() -> void:
	for child in _society_box.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			if child.has_method("on_select_handle"):
				child.call("on_select_handle")
			return


func _on_society_selected(card: Node) -> void:
	if _active_society != null and is_instance_valid(_active_society) and _active_society != card:
		if _active_society.has_method("out_select_card"):
			_active_society.call("out_select_card")
	_active_society = card
	for child in _player_box.get_children():
		child.queue_free()
	if card.has_method("populate_player_cards"):
		await card.call("populate_player_cards", _player_box)


func _on_player_card_id(scene_path: String) -> void:
	if _confirming or scene_path == "":
		return
	_confirming = true
	character_confirmed.emit(scene_path)


func _on_support_card_select(card: SupportCard) -> void:
	if card == null:
		return
	SupportData.game_support = card
	SupportData.get_card(card)
	Game.save_playerdata()
	_report_local_support()


# 上报本机所选支援 id + 其对 medical_kit 生成的影响给联机层（各端据此知道自己/他人的支援）
func _report_local_support() -> void:
	var coop = CoopNetScript.instance
	if coop == null or not coop.get("is_lan_game"):
		return
	var id: String = ""
	var mods: Dictionary = {}
	if SupportData.game_support != null:
		id = str(SupportData.game_support.support_id)
		mods = coop.call("_local_support_modifiers")
	coop.call("report_local_support", id, mods)


func _unhandled_input(event: InputEvent) -> void:
	# 被“已就绪/难度”遮罩覆盖期间不处理输入（尤其不吞 Esc），交给上层遮罩
	if not _interactive:
		return
	# 吞掉 Esc，避免弹出本体暂停菜单；房主在未选角色时按 Esc = 取消整轮选人回准备房
	if not (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		return
	get_viewport().set_input_as_handled()
	if _confirming:
		return
	var coop = CoopNetScript.instance
	if coop != null and multiplayer.is_server():
		coop.call("abort_select_to_lobby")
