extends Node2D

@export var shop_card: PackedScene
@export var shop_menu: Node

@onready var card_box: HBoxContainer = %card_box
@onready var sc: ScrollContainer = $Node2D/MarginContainer/ScrollContainer

@onready var support_halo: Sprite2D = %support_halo
@onready var support_sprite: Sprite2D = %support_sprite
@onready var main_name: Label = %MainName

@onready var exp_bar: TextureProgressBar = %exp_bar
@onready var exp_value: Label = %exp_value
@onready var support_name: Label = %support_name
@onready var weapon_name: Label = %weapon_name
@onready var weapon_icon: Sprite2D = %weapon_icon

@onready var main_anim: AnimationPlayer = $main_anim

@onready var lock_texture: TextureRect = %lock_texture

@onready var ps: Label = %ps
@onready var ex_skill: Label = %ex_skill

@onready var lv_value: Label = %lv_value
@onready var pa_value: Label = %pa_value
@onready var pa_id: Label = %pa_id

@onready var support_main: PanelContainer = %support_main
@onready var unlock_cost: Label = %unlock_cost

@onready var lv_anim: AnimationPlayer = $exp/lv_anim

var now_support_card: SupportCard
var main_on_select: bool = false
var on_lock: bool = false
var _lazy_active: bool = false
var _lazy_last_h: float = -1.0
var _lazy_force: int = 0

func _ready() -> void:
	support_main.mouse_entered.connect(main_card_mouse_in)
	support_main.mouse_exited.connect(main_card_mouse_out)
	support_main.gui_input.connect(main_card_select)
	GameEvents.support_card_select.connect(get_support_card)
	SupportData.count_exp_changed.connect(update_exp)
	SupportData.support_lv_up.connect(level_up_anim)
	SoundManager.voice_player.finished.connect(face_reset)
	add_shop_box()
	shop_menu.shop_open.connect(_on_shop_open)
	shop_menu.shop_close.connect(_on_shop_closed)


# 只在商店打开时按可见范围加载支援立绘，滚出即释放（+余量）。
# 仅在滚动位置变化（或刚打开的前几帧）时重算。
func _process(_delta: float) -> void:
	if not _lazy_active:
		return
	if sc == null:
		return
	var h := sc.get_h_scroll()
	if h == _lazy_last_h and _lazy_force <= 0:
		return
	_lazy_last_h = h
	if _lazy_force > 0:
		_lazy_force -= 1
	var view := sc.get_global_rect()
	for card in card_box.get_children():
		if not card.has_method("reveal"):
			continue
		var ctrl := card as Control
		if ctrl == null:
			continue
		if view.intersects(ctrl.get_global_rect().grow(150.0)):
			card.reveal()
		else:
			card.conceal()


func _on_shop_open() -> void:
	_lazy_active = true
	_lazy_force = 5
	_lazy_last_h = -1.0
	default_set()


func _on_shop_closed() -> void:
	_lazy_active = false
	_lazy_last_h = -1.0
	_lazy_force = 0
	for card in card_box.get_children():
		if card.has_method("conceal"):
			card.conceal()

func level_up_anim(_lv: int):
	SoundManager.play_sfx("PowerUp1")
	SupportData.level_up_voice()
	face_anim()
	update_exp()
	if !lv_anim.is_playing():
		lv_anim.play("lv_up")

func face_anim():
	var v = randi_range(0,1)
	if v == 1:
		support_sprite.frame = 0
	else:
		support_sprite.frame = 2

func face_reset():
	support_sprite.frame = 0

func default_set():
	var n = card_box.get_children()
	if !n.is_empty():
		n[0].card_anim.play("select_anim")
		n[0].emit_support_card()

func get_support_card(support_card: SupportCard):
	now_support_card = support_card
	SupportData.get_card(now_support_card)
	if now_support_card != null:
		change_card()

func update_exp():
	if now_support_card == null:
		return
	if SupportData.now_lv > 0:
		if SupportData.now_lv < now_support_card.max_lv:
			var percentage = float(SupportData.now_count_exp) / float(SupportData.next_exp)
			exp_value.text = str(SupportData.now_count_exp) + "/" + str(SupportData.next_exp)
			create_tween().tween_property(exp_bar, "value", percentage, 0.05 )
			create_tween().tween_property(exp_value, "position", Vector2(33, 6), 0.1).from(Vector2(33, 0))
		else:
			exp_value.text = "-/-"
			create_tween().tween_property(exp_bar, "value", 1, 0.05 )
		lv_value.text = "LV " + str(SupportData.now_lv)
		pa_value.text = "+" + str(round(SupportData.now_count_ability * 10000) * 0.01) + "%"
	else:
		lv_value.text = "LV -"
		exp_value.text = "-/-"

func update_card():
	SupportData.load_data()
	support_halo.texture = now_support_card.character_halo
	support_sprite.texture = LazyTexture.load_uncached(now_support_card.character_sprite_path)
	main_name.text = now_support_card.support_name
	support_name.text = now_support_card.support_name
	weapon_name.text = now_support_card.weapon_name
	weapon_icon.texture = now_support_card.weapon_icon
	
	ps.text = now_support_card.support_id + "_ps"
	ex_skill.text = now_support_card.support_id + "_ex"
	pa_id.text = now_support_card.pa_ability
	pa_value.text = "+" + str(round(SupportData.now_count_ability * 100)) + "%"
	
	unlock_cost.text = str(now_support_card.unlock_cost)
	
	if SupportData.support_data.has(now_support_card.support_id):
		lv_value.text = "LV " + str(SupportData.now_lv)
		update_exp()
		lock_texture.visible = false
		on_lock = false
	else:
		exp_bar.value = 0
		lv_value.text = "LV -"
		exp_value.text = "-/-"
		lock_texture.visible = true
		on_lock = true
	

func change_card():
	main_anim.play("change_card")
	await main_anim.animation_finished
	update_card()
	main_anim.play_backwards("change_card")
	await main_anim.animation_finished
	main_anim.play("loop_anim")

func add_shop_box():
	for i in SupportData.support_pool.size():
		var card_ins = shop_card.instantiate()
		card_ins.shop_card = SupportData.support_pool[i]
		card_box.add_child(card_ins)

func main_card_mouse_in():
	if on_lock == true:
		SoundManager.play_sfx("ButtonSounds2")

func main_card_mouse_out():
	if main_on_select == true and on_lock == true:
		main_anim.play_backwards("lock_select")
		main_on_select = false

func open_main_menu():
	main_on_select = true
	main_anim.play("lock_select")

func unlock_support():
	if PlayerData.player_pyroxenes >= now_support_card.unlock_cost:
		PlayerData.player_pyroxenes -= now_support_card.unlock_cost
		on_lock = false
		SupportData.add_new_data(now_support_card)
		Game.save_playerdata()
		SoundManager.play_sfx("CoinCostSounds")
		change_card()
	else:
		GameEvents.emit_pyroxenes_not_enough("Plana")

func main_card_select(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed and on_lock == true:
		if main_on_select == false:
			SoundManager.play_sfx("ButtonSounds")
			open_main_menu()
		else:
			unlock_support()
	
	if event.is_action_pressed("shoot") and on_lock == true:
		if main_on_select == false:
			SoundManager.play_sfx("ButtonSounds")
			open_main_menu()
		else:
			unlock_support()
