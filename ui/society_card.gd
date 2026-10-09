extends PanelContainer

@export_file("*.tscn") var player_card_1: String
@export_file("*.tscn") var player_card_2: String
@export_file("*.tscn") var player_card_3: String
@export_file("*.tscn") var player_card_4: String

@export var group_id: String

@onready var card_anim = $AnimationPlayer

var on_select: bool = false

@onready var card_group: Array =[player_card_1, player_card_2, player_card_3, player_card_4]

func _ready():
	mouse_entered.connect(mouse_select_anim)
	mouse_exited.connect(mouse_out_anim)
	gui_input.connect(on_select_card)
	check_group()
	PlayerData.pyroxenes_changed.connect(check_group)
	GameEvents.check_data.connect(check_group)

func check_group():
	if PlayerData.group.has(group_id):
		self.visible = true
	else:
		self.visible = false

# 由 menu_screen.society_card_filter 调用；MOD 社团卡覆写此方法。
# 只实例化「已解锁」角色；先不实例化地读出卡内 player_card.id 判断（兼容 uid:// 路径），
# 读不到时回退“实例化后判断并释放”，避免遗漏。
func populate_player_cards(box: Node) -> void:
	for path in card_group:
		if path == "":
			continue
		var pc = _peek_player_card(path)
		if pc != null and not PlayerData.character.has(pc.id):
			continue
		var card_ins = load(path).instantiate()
		var real_pc = card_ins.get("player_card")
		if real_pc == null or not PlayerData.character.has(real_pc.id):
			card_ins.free()
			continue
		box.add_child(card_ins)
		await get_tree().create_timer(0.07).timeout


# 不实例化卡场景，直接读 PackedScene 根节点导出的 player_card 资源。
func _peek_player_card(scene_path: String):
	var ps = load(scene_path)
	if ps == null or not (ps is PackedScene):
		return null
	var st = (ps as PackedScene).get_state()
	if st == null or st.get_node_count() == 0:
		return null
	for i in st.get_node_property_count(0):
		if String(st.get_node_property_name(0, i)) == "player_card":
			return st.get_node_property_value(0, i)
	return null

func open_card():
	mouse_filter = 0

func close_card():
	mouse_filter = 2

func mouse_select_anim():
	if on_select == false:
		SoundManager.play_sfx("ButtonSounds2")
		card_anim.play("select_anim")

func mouse_out_anim():
	if on_select == false:
		card_anim.play("out_anim")

func on_select_card(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed and on_select == false:
		SoundManager.play_sfx("ButtonSounds")
		on_select_handle()
	
	if event.is_action_pressed("shoot") and on_select == false:
		SoundManager.play_sfx("ButtonSounds")
		on_select_handle()

func on_select_handle():
	on_select = true
	card_anim.play("on_select_anim")
	GameEvents.emit_society_card_selected(self)
	close_card()
	#await card_anim.animation_finished
	#close_card.call_deferred()

func out_select_card():
	if on_select == true:
		on_select = false
		card_anim.play("out_select_anim")
		await get_tree().create_timer(0.3).timeout
		open_card()
