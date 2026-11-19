extends PanelContainer

@onready var item_icon = $Node2D/TextureRect

var card_id: String
var _tooltip: HoverTooltipBinding

func _ready() -> void:
	_tooltip = HoverTooltipBinding.bind(self, _tooltip_content, func(): return not card_id.is_empty())
	gui_input.connect(touch_show)

func touch_show(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tooltip.preview("touch", event.index)

func _tooltip_content() -> Array:
	return [
		{"text": card_id + "_id", "role": "title"},
		# 说明允许有意留空：optional 段无译文时整段跳过，不显示键名。
		{"text": card_id + "_description", "optional": true},
	]

func set_gamemode_card(card: GameMode) -> void:
	if card != null:
		item_icon.texture = card.game_mode_icon
		card_id = card.game_mode_id
		_tooltip.refresh()
