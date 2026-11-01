class_name AbilityShopCardBase
extends PanelContainer

## 能力商店卡（道具升级卡 / PS 卡）共用输入、悬停与购买流程；
## 升级上限、购买后的应用、价格与文案由子类负责（同 ShopPurchaseCard 模式）。

@onready var upgrade = $Node2D/upgrade
@onready var marker_2d = $Marker2D
## 整卡触屏归属区来源：卡面矩形（成本条与图标同属一张卡）。
@onready var press_area: Control = get_node_or_null("Node2D/ColorRect3") as Control
@onready var smoke = preload("res://scenes/bullet/spread_smoke.tscn")

var t_num: int = 0
var icon_num: int = 0
var coin_cost: int = 0

var on_touch: bool = false
var _tooltip: HoverTooltipBinding

var player: Node

var rare_color: Array[Color] = [ Color(0.779, 0.795, 0.81), Color(0.464, 0.673, 0.832), Color(0.884, 0.764, 0.435), Color(0.985, 0.643, 0.909) ]

func _ready() -> void:
	_tooltip = HoverTooltipBinding.bind(upgrade, _tooltip_content, func(): return player != null, func(): on_touch = false)
	_tooltip.press_bounds = _press_bounds
	upgrade.mouse_entered.connect(mouse_in)
	upgrade.mouse_exited.connect(mouse_out)
	upgrade.gui_input.connect(mouse_selected.bind(upgrade))
	GameEvents.get_player.connect(get_player)
	GameEvents.player_card_touch.connect(touch_out)
	_on_ready_extra()

## 整卡触屏归属区：第二下点按图标也必须计入确认，不能被宿主当成「点别处」而清掉确认态。
func _press_bounds() -> Rect2:
	var area: Control = press_area if press_area != null else upgrade
	return area.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, area.size)

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	reset_data()

func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D/upgrade/AnimationPlayer.play("mouse_in")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")

func mouse_out():
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")

func touch_out() -> void:
	_tooltip.dismiss()
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")

func touch_button(mode: String = "touch", index: int = -1):
	if not on_touch:
		GameEvents.emit_player_card_touch()
		on_touch = true
		mouse_in()
		_tooltip.preview(mode, index)
	else:
		_attempt_purchase()

func mouse_selected(event: InputEvent, source: Control = null):
	if event is InputEventScreenTouch:
		if _tooltip.tapped(event, source):
			touch_button("touch", event.index)
		return

	if event.is_action_pressed("shoot"):
		_attempt_purchase()

# 二次确认：超上限或余额不足播 coin_lack，否则扣款、升级并交给子类应用效果
func _attempt_purchase():
	if t_num >= _upgrade_cap():
		$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		return

	if player.stats.usable_coin < coin_cost:
		$Node2D/upgrade/AnimationPlayer.play("coin_lack")
	else:
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_player_coins_cost(coin_cost)
		item_upgrade()
		_on_purchased()

func smoke_anim():
	var ins = smoke.instantiate()
	ins.position = marker_2d.position
	add_child(ins)

func preview_from_navigation() -> void:
	GameEvents.emit_player_card_touch()
	on_touch = true
	mouse_in()
	_tooltip.preview("focus")

## 子类：tooltip 文本（HoverTooltipBinding 内容回调）。
func _tooltip_content() -> Array:
	return []

## 子类：升级次数上限（达到后播 coin_lack 并由子类显示 MAX）。
func _upgrade_cap() -> int:
	return 0

## 子类：执行一次升级推进并刷新展示（达到上限时早退）。
func item_upgrade() -> void:
	pass

## 子类：扣款成功、item_upgrade() 之后的属性/事件应用。
func _on_purchased() -> void:
	pass

## 子类：公共 _ready 之后的数据填充与信号接线。
func _on_ready_extra() -> void:
	pass

## 子类：重置为初始展示状态（get_player 时调用）。
func reset_data() -> void:
	pass
